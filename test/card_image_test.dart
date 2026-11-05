import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_mymc/dart_mymc.dart';
// ignore: implementation_imports
import 'package:dart_mymc/src/ps2mc.dart';
import 'package:mymc_web/card_image.dart';
import 'package:test/test.dart';

void main() {
  final payload = Uint8List.fromList(
    List.generate(4097, (i) => (i * 31) % 256),
  );
  Ps2Save save(String name) =>
      Ps2Save.fromFiles(name, {'data.bin': payload, 'empty': Uint8List(0)});

  for (final size in CardImage.sizesMb) {
    test(
      '$size MB MCD creation, editing, and PS2 round trip',
      () {
        final card = CardImage.create(sizeMb: size);
        card.importSave(save('BASLUS-TEST').toBytes());
        final raw = CardImage.export(card, CardFormat.mcd);
        expect(raw.length, size * 1024 * 1024);
        expect(CardImage.detectFormat(raw), CardFormat.mcd);
        final ps2 = CardImage.convert(raw, CardFormat.ps2);
        expect(ps2.length, size * 1024 * 1024 ~/ 512 * 528);
        expect(CardImage.detectFormat(ps2), CardFormat.ps2);
        expect(
          sha256.convert(CardImage.convert(ps2, CardFormat.mcd)),
          sha256.convert(raw),
        );

        final reopened = CardImage.open(raw);
        expect(reopened.listSaves().single.dirName, 'BASLUS-TEST');
        final restored = Ps2Save.fromBytes(reopened.exportSave('BASLUS-TEST'));
        expect(
          restored.files
              .firstWhere((file) => file.name == 'data.bin')
              .toBytes(),
          payload,
        );
        reopened.importSave(save('SECOND').toBytes());
        reopened.deleteSave('BASLUS-TEST');
        final edited = CardImage.open(
          CardImage.export(reopened, CardFormat.mcd),
        );
        expect(edited.listSaves().map((s) => s.dirName), ['SECOND']);
        edited.close();
        reopened.close();
        card.close();
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  test(
    'existing PCSX2 image keeps every data page, including unused bytes',
    () {
      final card = Ps2Card.format();
      card.importSave(save('FIRST').toBytes());
      final original = Uint8List.fromList(card.toBytes());
      final raw = CardImage.convert(original, CardFormat.mcd);
      for (var page = 0; page < raw.length ~/ 512; page++) {
        for (var offset = 0; offset < 512; offset++) {
          if (raw[page * 512 + offset] != original[page * 528 + offset]) {
            fail('Data changed at page $page, offset $offset');
          }
        }
      }
      expect(sha256.convert(card.toBytes()), sha256.convert(original));
      final converted = CardImage.open(CardImage.convert(raw, CardFormat.ps2));
      expect(converted.listSaves().single.dirName, 'FIRST');
      converted.close();
      card.close();
    },
  );

  test('PS2 conversion emits known ECC vectors and zero spare padding', () {
    final card = CardImage.create(sizeMb: 1);
    final raw = CardImage.export(card, CardFormat.mcd);
    // A single low bit in byte 0 has ECC 70 00 7f; all-zero data is 77 7f 7f.
    raw.fillRange(512, 1024, 0);
    raw[512] = 1;
    final ps2 = CardImage.convert(raw, CardFormat.ps2);
    expect(ps2.sublist(528 + 512, 528 + 528), [
      0x70,
      0x00,
      0x7f,
      0x77,
      0x7f,
      0x7f,
      0x77,
      0x7f,
      0x7f,
      0x77,
      0x7f,
      0x7f,
      0,
      0,
      0,
      0,
    ]);
    card.close();
  });

  test(
    'ZIP includes root files, hidden directories, nested and empty folders',
    () {
      final base = CardImage.create(sizeMb: 1);
      final mc = Ps2MemoryCard.fromIo(MemoryCardIo(base.toBytes()));
      mc.mkdir('/SAVE');
      mc.mkdir('/SAVE/nested');
      mc.mkdir('/EMPTY');
      mc.mkdir('/SYS');
      final root = mc.dirOpen('/', mode: 'r+b');
      for (var i = 0; i < root.entryCount; i++) {
        final entry = root[i];
        if (entry.name == 'SYS') {
          root.writeRawEnt(i, entry.copyWith(mode: entry.mode | 0x2000));
        }
      }
      root.close();
      for (final path in [
        '/root.bin',
        '/SAVE/nested/data.bin',
        '/SYS/settings',
      ]) {
        final file = mc.open(path, mode: 'wb');
        file.write(payload);
        file.close();
      }
      final zero = mc.open('/SAVE/empty.bin', mode: 'wb');
      zero.close();
      final card = CardImage.open(mc.toBytes());
      final before = sha256.convert(card.toBytes());
      final zip = ZipDecoder().decodeBytes(
        CardImage.exportContentsZip(card),
        verify: true,
      );
      expect(zip.map((file) => file.name).toSet(), {
        'root.bin',
        'SAVE/',
        'SAVE/nested/',
        'SAVE/nested/data.bin',
        'SAVE/empty.bin',
        'EMPTY/',
        'SYS/',
        'SYS/settings',
      });
      expect(zip.findFile('SAVE/nested/data.bin')!.content, payload);
      expect(zip.findFile('root.bin')!.content, payload);
      expect(zip.findFile('SYS/settings')!.content, payload);
      expect(zip.findFile('EMPTY/')!.isFile, isFalse);
      expect(zip.findFile('SAVE/empty.bin')!.size, 0);
      expect(sha256.convert(card.toBytes()), before);
      card.close();
      mc.close();
      base.close();
    },
  );

  test('blank card exports a valid empty ZIP', () {
    final card = CardImage.create(sizeMb: 1);
    expect(
      ZipDecoder().decodeBytes(CardImage.exportContentsZip(card)),
      isEmpty,
    );
    card.close();
  });

  test('save-folder ZIP import and cross-format save copy survive export', () {
    final source = CardImage.create(sizeMb: 1);
    CardImage.importSave(source, save('ONE').toZip(), 'saves.ZIP');
    CardImage.importSave(source, save('TWO').toBytes(), 'save.psu');
    final dest = CardImage.open(CardImage.export(source, CardFormat.mcd));
    dest.deleteSave('TWO');
    dest.importSave(source.exportSave('TWO'));
    final zip = CardImage.exportContentsZip(dest);
    final imported = CardImage.create(sizeMb: 1);
    CardImage.importSave(imported, zip, 'contents.zip');
    expect(imported.listSaves().map((s) => s.dirName).toSet(), {'ONE', 'TWO'});
    expect(
      Ps2Save.fromBytes(imported.exportSave('TWO')).files.first.toBytes(),
      payload,
    );
    imported.close();
    dest.close();
    source.close();
  });

  test('rejects PS1, invalid, truncated, oversized and damaged ECC images', () {
    expect(() => CardImage.open(Uint8List(10)), throwsFormatException);
    final ps1 = Uint8List(128 * 1024)
      ..[0] = 0x4d
      ..[1] = 0x43;
    expect(
      () => CardImage.open(ps1),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('PS1'),
        ),
      ),
    );
    final card = CardImage.create(sizeMb: 1);
    final raw = CardImage.export(card, CardFormat.mcd);
    expect(
      () => CardImage.open(Uint8List.sublistView(raw, 0, raw.length - 1)),
      throwsFormatException,
    );
    expect(
      () => CardImage.open(Uint8List(raw.length + 1)..setAll(0, raw)),
      throwsFormatException,
    );
    final ps2 = card.toBytes();
    ps2[512] ^= 3;
    expect(() => CardImage.open(ps2), throwsFormatException);
    final badGeometry = Uint8List.fromList(raw);
    ByteData.sublistView(badGeometry).setUint16(40, 1024, Endian.little);
    expect(() => CardImage.open(badGeometry), throwsFormatException);
    final badPointer = Uint8List.fromList(raw);
    ByteData.sublistView(badPointer).setUint32(80, 0x7fffffff, Endian.little);
    expect(() => CardImage.open(badPointer).info, throwsFormatException);
    card.close();
  });

  test(
    'ZIP refuses directory cycles instead of silently omitting contents',
    () {
      final base = CardImage.create(sizeMb: 1);
      final mc = Ps2MemoryCard.fromIo(MemoryCardIo(base.toBytes()));
      mc.mkdir('/LOOP');
      final root = mc.dirOpen('/', mode: 'r+b');
      final dot = root[0];
      root.writeRawEnt(2, root[2].copyWith(fatCluster: dot.fatCluster));
      root.close();
      final card = CardImage.open(mc.toBytes());
      expect(() => CardImage.exportContentsZip(card), throwsFormatException);
      card.close();
      mc.close();
      base.close();
    },
  );

  test(
    'extensions are case insensitive and conversion replaces the suffix',
    () {
      expect(CardImage.isCardFilename('Card.MCD'), isTrue);
      expect(CardImage.isCardFilename('Card.PS2'), isTrue);
      expect(CardImage.isCardFilename('save.psu'), isFalse);
      expect(CardImage.downloadName('Card.MCD', 'ps2'), 'Card.ps2');
      expect(CardImage.downloadName('Card.PS2', 'mcd'), 'Card.mcd');
      expect(
        CardImage.downloadName('my.ps2.card.mcd', 'zip'),
        'my.ps2.card.zip',
      );
    },
  );
}
