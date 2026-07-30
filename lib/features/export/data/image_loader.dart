import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/export_exception.dart';
import '../domain/models/book.dart';

/// Lê uma imagem do disco para dentro do livro.
///
/// JPEG, PNG e GIF entram como estão — são os tipos que todo leitor de EPUB
/// aceita. Qualquer outro (WebP, BMP, TIFF…) é convertido para JPEG: o
/// arquivo até seria válido em EPUB 3.3, mas Kindle e leitores antigos
/// mostrariam um retângulo vazio no lugar da capa.
Future<BookCover> loadExportImage(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw ExportException('Imagem não encontrada: $path');
  }

  final bytes = await file.readAsBytes();
  final known = _detectFormat(bytes);
  if (known != null) {
    return BookCover(
      bytes: bytes,
      mediaType: known.mediaType,
      extension: known.extension,
    );
  }

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw ExportException(
      'Não foi possível ler a imagem "${file.uri.pathSegments.last}". '
      'Use JPEG, PNG ou GIF.',
    );
  }
  return BookCover(
    bytes: img.encodeJpg(decoded, quality: 90),
    mediaType: 'image/jpeg',
    extension: 'jpg',
  );
}

typedef _ImageFormat = ({String mediaType, String extension});

/// Pelos bytes iniciais, e não pela extensão do arquivo: `.jpg` com PNG
/// dentro é comum o bastante para quebrar a capa de quem exporta.
_ImageFormat? _detectFormat(Uint8List bytes) {
  if (bytes.length < 12) return null;

  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return (mediaType: 'image/jpeg', extension: 'jpg');
  }
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return (mediaType: 'image/png', extension: 'png');
  }
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    return (mediaType: 'image/gif', extension: 'gif');
  }
  return null;
}
