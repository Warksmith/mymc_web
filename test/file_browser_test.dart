import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_mymc/dart_mymc.dart';
// ignore: implementation_imports
import 'package:dart_mymc/src/ps2mc.dart';
import 'package:mymc_web/card_image.dart';
import 'package:test/test.dart';

void main() {
  late Ps2Card card;
  final data = Uint8List.fromList([0, 255, 1, 128, 4]);
  setUp(() {
    final base = CardImage.create(sizeMb: 1);
    final mc = Ps2MemoryCard.fromIo(MemoryCardIo(base.toBytes()));
    for (final path in ['/SAVE', '/SAVE/nested', '/EMPTY', '/SYSTEM']) {
      mc.mkdir(path);
    }
    for (final path in [
      '/root.bin',
      '/SAVE/nested/data.bin',
      '/SAVE/notes<&>.txt',
      '/SYSTEM/config',
    ]) {
      final file = mc.open(path, mode: 'wb');
      file.write(data);
      file.close();
    }
    mc.open('/SAVE/zero', mode: 'wb').close();
    final root = mc.dirOpen('/', mode: 'r+b');
    for (var i = 0; i < root.entryCount; i++) {
      final entry = root[i];
      if (entry.name == 'SYSTEM') {
        root.writeRawEnt(i, entry.copyWith(mode: entry.mode | 0x2000));
      }
    }
    root.close();
    card = CardImage.open(CardImage.convert(mc.toBytes(), CardFormat.mcd));
    mc.close();
    base.close();
  });
  tearDown(() => card.close());

  test(
    'lists actual folders and files, with folders first and file metadata',
    () {
      final before = sha256.convert(card.toBytes());
      final root = CardImage.listDirectory(card);
      expect(root.map((e) => e.name), ['EMPTY', 'SAVE', 'SYSTEM', 'root.bin']);
      expect(root.first.isDirectory, isTrue);
      expect(root.last.isDirectory, isFalse);
      expect(root.last.sizeBytes, data.length);
      expect(root.last.modified.year, greaterThanOrEqualTo(2026));
      final nested = CardImage.listDirectory(card, 'SAVE/nested');
      expect(nested.single.path, 'SAVE/nested/data.bin');
      expect(CardImage.listDirectory(card, 'EMPTY'), isEmpty);
      expect(CardImage.listDirectory(card, 'SAVE').map((e) => e.name), [
        'nested',
        'notes<&>.txt',
        'zero',
      ]);
      expect(sha256.convert(card.toBytes()), before);
    },
  );

  test('reads nested and zero-byte files without save-format wrapping', () {
    expect(CardImage.readFile(card, 'SAVE/nested/data.bin'), data);
    expect(CardImage.readFile(card, 'root.bin'), data);
    expect(CardImage.readFile(card, 'SAVE/zero'), isEmpty);
    expect(() => CardImage.readFile(card, 'SAVE'), throwsA(isA<Ps2McError>()));
    expect(
      () => CardImage.readFile(card, 'missing'),
      throwsA(isA<Ps2McError>()),
    );
  });

  test(
    'selected ZIP includes full folders and deduplicates parent/child selections',
    () {
      final zip = ZipDecoder().decodeBytes(
        CardImage.exportContentsZip(
          card,
          paths: [
            'SAVE/nested/data.bin',
            'SAVE/nested',
            'SAVE',
            'SAVE',
            'root.bin',
            'EMPTY',
          ],
        ),
      );
      expect(zip.map((e) => e.name).toSet(), {
        'SAVE/',
        'SAVE/nested/',
        'SAVE/nested/data.bin',
        'SAVE/notes<&>.txt',
        'SAVE/zero',
        'root.bin',
        'EMPTY/',
      });
      expect(zip.length, 7);
      expect(zip.findFile('SAVE/nested/data.bin')!.content, data);
      expect(zip.findFile('EMPTY/')!.isFile, isFalse);
      expect(zip.findFile('SYSTEM/'), isNull);
      final all = ZipDecoder().decodeBytes(CardImage.exportContentsZip(card));
      expect(all.findFile('SYSTEM/config')!.content, data);
    },
  );

  test('single selected file retains its full path in ZIP', () {
    final zip = ZipDecoder().decodeBytes(
      CardImage.exportContentsZip(card, paths: ['SAVE/nested/data.bin']),
    );
    expect(zip.single.name, 'SAVE/nested/data.bin');
    expect(zip.single.content, data);
  });

  test('invalid paths and empty or missing selections fail explicitly', () {
    for (final path in [
      '',
      '../root.bin',
      '/root.bin',
      'SAVE//zero',
      r'SAVE\zero',
      'C:root.bin',
    ]) {
      expect(() => CardImage.readFile(card, path), throwsFormatException);
      expect(
        () => CardImage.exportContentsZip(card, paths: [path]),
        throwsFormatException,
      );
    }
    expect(() => CardImage.listDirectory(card, '..'), throwsFormatException);
    expect(
      () => CardImage.listDirectory(card, 'missing'),
      throwsA(isA<Ps2McError>()),
    );
    expect(
      () => CardImage.exportContentsZip(card, paths: []),
      throwsFormatException,
    );
    expect(
      () => CardImage.exportContentsZip(card, paths: ['missing']),
      throwsFormatException,
    );
  });
}
