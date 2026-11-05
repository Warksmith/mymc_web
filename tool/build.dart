import 'dart:io';

/// Rebuild the committed GitHub Pages site, preserving docs/saves.
Future<void> main() async {
  final output = Directory('docs')..createSync(recursive: true);
  final result = await Process.start(Platform.resolvedExecutable, [
    'compile',
    'js',
    '-O2',
    '--no-source-maps',
    '-o',
    '${output.path}/main.dart.js',
    'web/main.dart',
  ], mode: ProcessStartMode.inheritStdio);
  final code = await result.exitCode;
  if (code != 0) {
    exitCode = code;
    return;
  }
  for (final file in Directory('web').listSync().whereType<File>()) {
    if (file.path.endsWith('.dart')) continue;
    file.copySync('${output.path}/${file.uri.pathSegments.last}');
  }
  File('${output.path}/.nojekyll').writeAsStringSync('');
  stdout.writeln('Built GitHub Pages site in docs/');
}
