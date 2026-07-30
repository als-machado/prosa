import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prosa/features/export/data/image_loader.dart';
import 'package:prosa/features/export/domain/export_exception.dart';

late Directory _dir;

img.Image get _sample => img.Image(width: 4, height: 6)
  ..clear(img.ColorRgb8(200, 100, 50));

Future<String> _writeImage(String name, List<int> bytes) async {
  final file = File('${_dir.path}/$name');
  await file.writeAsBytes(bytes);
  return file.path;
}

void main() {
  setUp(() async {
    _dir = await Directory.systemTemp.createTemp('prosa_cover_test');
  });

  tearDown(() async {
    if (await _dir.exists()) await _dir.delete(recursive: true);
  });

  test('PNG entra como está', () async {
    final bytes = img.encodePng(_sample);
    final cover = await loadExportImage(await _writeImage('capa.png', bytes));

    expect(cover.mediaType, 'image/png');
    expect(cover.extension, 'png');
    expect(cover.bytes, bytes);
  });

  test('JPEG entra como está, mesmo com a extensão errada', () async {
    // O tipo sai dos bytes iniciais: ".png" com JPEG dentro é comum o
    // bastante para quebrar a capa de quem exporta.
    final bytes = img.encodeJpg(_sample);
    final cover = await loadExportImage(await _writeImage('capa.png', bytes));

    expect(cover.mediaType, 'image/jpeg');
    expect(cover.bytes, bytes);
  });

  test('formato fora dos três aceitos é convertido para JPEG', () async {
    final path = await _writeImage('capa.bmp', img.encodeBmp(_sample));
    final cover = await loadExportImage(path);

    expect(cover.mediaType, 'image/jpeg');
    expect(cover.extension, 'jpg');
    expect(img.decodeJpg(cover.bytes)?.width, 4);
  });

  test('arquivo ilegível vira erro com mensagem de gente', () async {
    final path = await _writeImage('capa.jpg', List.filled(64, 0x41));

    expect(
      () => loadExportImage(path),
      throwsA(
        isA<ExportException>().having(
          (e) => e.message,
          'mensagem',
          contains('JPEG, PNG ou GIF'),
        ),
      ),
    );
  });

  test('arquivo que não existe vira erro', () async {
    expect(
      () => loadExportImage('${_dir.path}/nao_existe.png'),
      throwsA(isA<ExportException>()),
    );
  });
}
