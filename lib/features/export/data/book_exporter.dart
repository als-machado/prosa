import 'dart:typed_data';

import '../domain/models/book.dart';
import '../domain/models/export_format.dart';

/// Serializa um [Book] já montado no formato de saída.
///
/// Quem lê o disco é o `BookBuilder`; daqui para frente é só escrever bytes.
/// É este contrato que faz DOCX, PDF, ODT, HTML e TXT serem trabalho de um
/// arquivo novo cada, e não de uma segunda leitura do projeto.
abstract interface class BookExporter {
  ExportFormat get format;

  /// [modified] entra nos metadados de data do arquivo; existe como parâmetro
  /// para que o teste consiga comparar a saída byte a byte.
  Future<Uint8List> build(Book book, {DateTime? modified});
}
