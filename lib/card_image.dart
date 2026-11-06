import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dart_mymc/dart_mymc.dart';
// The pinned library facade does not expose page conversion or recursive export.
// Keep its internal API usage isolated here.
// ignore: implementation_imports
import 'package:dart_mymc/src/ps2mc.dart';
// ignore: implementation_imports
import 'package:dart_mymc/src/ps2mc_ecc.dart';
// ignore: implementation_imports
import 'package:dart_mymc/src/ps2mc_dir.dart' show PS2DirEntry;

enum CardFormat { ps2, mcd }

class CardEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;
  final DateTime modified;

  const CardEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.sizeBytes,
    required this.modified,
  });
}

/// PS2 MCD stores 512-byte pages; PCSX2 PS2 adds 16 spare/ECC bytes per page.
/// Filenames do not determine the actual storage layout.
class CardImage {
  static const sizesMb = [1, 2, 4, 8, 16, 32, 64, 128];
  static const _magic = 'Sony PS2 Memory Card Format ';
  static const _pageSize = 512;
  static const _rawPageSize = 528;

  static bool isCardFilename(String name) =>
      RegExp(r'\.(ps2|mcd)$', caseSensitive: false).hasMatch(name);

  static String downloadName(String name, String extension) =>
      '${name.replaceFirst(RegExp(r'\.(ps2|mcd)$', caseSensitive: false), '')}.$extension';

  /// Validate the header and exact length before the library can read the image.
  static CardFormat detectFormat(Uint8List bytes) {
    if (bytes.length == 128 * 1024 && bytes[0] == 0x4d && bytes[1] == 0x43) {
      throw const FormatException(
        'This is a PS1 card. Only PS2 cards are supported.',
      );
    }
    if (bytes.length < _pageSize ||
        String.fromCharCodes(bytes.take(_magic.length)) != _magic) {
      throw const FormatException('Not a formatted PS2 memory card image.');
    }
    final header = ByteData.sublistView(bytes);
    final pageSize = header.getUint16(40, Endian.little);
    final pagesPerCluster = header.getUint16(42, Endian.little);
    final pagesPerBlock = header.getUint16(44, Endian.little);
    final clusters = header.getUint32(48, Endian.little);
    final dataSize = clusters * pagesPerCluster * pageSize;
    if (pageSize != _pageSize ||
        pagesPerCluster != 2 ||
        pagesPerBlock != 16 ||
        !sizesMb.any((size) => dataSize == size * 1024 * 1024)) {
      throw const FormatException(
        'Unsupported PS2 card geometry (expected 1–128 MB).',
      );
    }
    if (bytes.length == dataSize) return CardFormat.mcd;
    if (bytes.length == dataSize ~/ _pageSize * _rawPageSize) {
      // Do not let the library mistake a damaged ECC header for a raw image.
      final result = eccCheckPage(
        Uint8List.sublistView(bytes, 0, _pageSize),
        Uint8List.sublistView(bytes, _pageSize, _rawPageSize),
      );
      if (result.status == eccCheckFailed) {
        throw const FormatException(
          'The PS2 card header has an unrecoverable ECC error.',
        );
      }
      return CardFormat.ps2;
    }
    throw const FormatException(
      'Card size does not match its header; the image may be truncated.',
    );
  }

  /// Convert every page, including unallocated space and filesystem metadata.
  /// Regenerated spare bytes contain four 3-byte ECC codes and four zero bytes.
  static Uint8List convert(Uint8List bytes, CardFormat target) {
    final source = detectFormat(bytes);
    if (source == target) return Uint8List.fromList(bytes);
    final sourceStride = source == CardFormat.ps2 ? _rawPageSize : _pageSize;
    final targetStride = target == CardFormat.ps2 ? _rawPageSize : _pageSize;
    final pages = bytes.length ~/ sourceStride;
    final result = Uint8List(pages * targetStride);
    for (var i = 0; i < pages; i++) {
      final page = Uint8List.sublistView(
        bytes,
        i * sourceStride,
        i * sourceStride + _pageSize,
      );
      final start = i * targetStride;
      result.setRange(start, start + _pageSize, page);
      if (target == CardFormat.ps2) {
        final codes = eccCalculatePage(page);
        for (var chunk = 0; chunk < codes.length; chunk++) {
          result.setRange(
            start + _pageSize + chunk * 3,
            start + _pageSize + chunk * 3 + 3,
            codes[chunk],
          );
        }
      }
    }
    return result;
  }

  // Keep the editing backend in ECC layout to avoid its heuristic raw detection.
  static Ps2Card open(Uint8List bytes) =>
      Ps2Card.fromIo(_FixedCardIo(convert(bytes, CardFormat.ps2)));

  static Ps2Card create({int sizeMb = 8}) {
    if (!sizesMb.contains(sizeMb)) throw ArgumentError.value(sizeMb, 'sizeMb');
    final pages = sizeMb * 1024 * 1024 ~/ _pageSize;
    final mc = Ps2MemoryCard.fromIo(
      MemoryCardIo.blank(pages * _rawPageSize),
      formatParams: [1, _pageSize, 16, pages],
    );
    final bytes = mc.toBytes();
    mc.close();
    return Ps2Card.fromIo(_FixedCardIo(bytes));
  }

  static Uint8List export(Ps2Card card, CardFormat format) =>
      convert(card.toBytes(), format);

  static void _validatePath(String path, {bool allowRoot = false}) {
    if (path.isEmpty && allowRoot) return;
    if (path.isEmpty ||
        path.contains(RegExp(r'[\\:\x00]')) ||
        path
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const FormatException('Invalid card path.');
    }
  }

  /// Paths are relative to the card root; an empty string lists the root.
  static List<CardEntry> listDirectory(Ps2Card card, [String path = '']) {
    _validatePath(path, allowRoot: true);
    final mc = Ps2MemoryCard.fromIo(_FixedCardIo(card.toBytes()));
    try {
      final dir = mc.dirOpen('/$path');
      try {
        final entries = <CardEntry>[];
        for (final entry in dir) {
          if (!entry.exists || entry.name == '.' || entry.name == '..') {
            continue;
          }
          final childPath = path.isEmpty ? entry.name : '$path/${entry.name}';
          _validatePath(childPath);
          entries.add(
            CardEntry(
              name: entry.name,
              path: childPath,
              isDirectory: entry.isDir,
              sizeBytes: entry.isDir ? 0 : entry.length,
              modified: entry.modified.toLocalDateTime(),
            ),
          );
        }
        entries.sort((a, b) {
          if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return entries;
      } finally {
        dir.close();
      }
    } finally {
      mc.close();
    }
  }

  static Uint8List readFile(Ps2Card card, String path) {
    _validatePath(path);
    final mc = Ps2MemoryCard.fromIo(_FixedCardIo(card.toBytes()));
    try {
      final file = mc.open('/$path');
      try {
        final data = file.read();
        if (data.length != file.length) {
          throw FormatException('Incomplete file on card: $path');
        }
        return data;
      } finally {
        file.close();
      }
    } finally {
      mc.close();
    }
  }

  /// Export every live file and directory, including root files, empty folders,
  /// hidden/system data, and nested directories. This is a contents archive;
  /// use a card image when filesystem attributes or deleted data must survive.
  /// If [paths] is supplied, export those files/folders recursively, retaining
  /// their paths relative to the card root. Overlapping selections are deduped.
  static Uint8List exportContentsZip(Ps2Card card, {Iterable<String>? paths}) {
    final requested = paths?.toSet().toList();
    if (requested != null) {
      if (requested.isEmpty) {
        throw const FormatException('Select at least one item.');
      }
      for (final path in requested) {
        _validatePath(path);
      }
    }
    final selected = requested
        ?.where(
          (path) => !requested.any((parent) => path.startsWith('$parent/')),
        )
        .toList();
    final mc = Ps2MemoryCard.fromIo(_FixedCardIo(card.toBytes()));
    final archive = Archive();
    final visited = <int>{mc.rootdirFatCluster};
    late void Function(String) visit;
    void addEntry(String name, PS2DirEntry entry) {
      _validatePath(name);
      if (entry.isDir) {
        if (!visited.add(entry.fatCluster)) {
          throw const FormatException(
            'Card contains a directory cycle or cross-link.',
          );
        }
        archive.addFile(ArchiveFile('$name/', 0, <int>[])..isFile = false);
        visit(name);
      } else {
        final file = mc.open('/$name');
        try {
          final data = file.read();
          if (data.length != entry.length) {
            throw FormatException('Incomplete file on card: $name');
          }
          archive.addFile(
            ArchiveFile(name, data.length, data)
              ..lastModTime = entry.modified.toUnixTimestamp(),
          );
        } finally {
          file.close();
        }
      }
    }

    visit = (String path) {
      final dir = mc.dirOpen(path.isEmpty ? '/' : '/$path');
      try {
        for (final entry in dir) {
          if (!entry.exists || entry.name == '.' || entry.name == '..') {
            continue;
          }
          if (entry.name.isEmpty ||
              entry.name.contains(RegExp(r'[/\\:\x00]'))) {
            throw const FormatException(
              'Card contains an unsafe archive filename.',
            );
          }
          final name = path.isEmpty ? entry.name : '$path/${entry.name}';
          addEntry(name, entry);
        }
      } finally {
        dir.close();
      }
    };

    try {
      if (selected == null) {
        visit('');
      } else {
        for (final path in selected) {
          final entry = mc.pathSearch('/$path').ent;
          if (!entry.exists) {
            throw FormatException('Item no longer exists: $path');
          }
          addEntry(path, entry);
        }
      }
      return Uint8List.fromList(ZipEncoder().encode(archive)!);
    } finally {
      mc.close();
    }
  }

  static void importSave(Ps2Card card, Uint8List bytes, String filename) {
    if (filename.toLowerCase().endsWith('.zip')) {
      card.importZip(bytes, overwrite: true);
    } else {
      card.importSave(bytes, overwrite: true);
    }
  }
}

/// The upstream memory backend grows even on reads. A damaged filesystem
/// pointer must fail, rather than allocating beyond the card's declared size.
class _FixedCardIo extends MemoryCardIo {
  final int _length;
  int _position = 0;

  _FixedCardIo(super.bytes) : _length = bytes.length;

  @override
  void setPosition(int offset) {
    if (offset < 0 || offset > _length) {
      throw const FormatException('Filesystem points outside the memory card.');
    }
    super.setPosition(offset);
    _position = offset;
  }

  void _advance(int count) {
    if (count < 0 || count > _length - _position) {
      throw const FormatException('Filesystem extends beyond the memory card.');
    }
    _position += count;
  }

  @override
  Uint8List read(int length) {
    _advance(length);
    return super.read(length);
  }

  @override
  void write(Uint8List data) {
    _advance(data.length);
    super.write(data);
  }
}
