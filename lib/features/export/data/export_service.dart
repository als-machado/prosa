import 'dart:typed_data';

import '../../../core/utils/file_name_sanitizer.dart';
import '../../../shared/models/prosa_project.dart';
import '../../projects/presentation/providers/project_tree_provider.dart';
import '../domain/book_builder.dart';
import '../domain/export_exception.dart';
import '../domain/models/book.dart';
import '../domain/models/export_format.dart';
import 'book_exporter.dart';
import 'docx_exporter.dart';
import 'epub_exporter.dart';
import 'export_config_store.dart';
import 'html_exporter.dart';
import 'image_loader.dart';
import 'odt_exporter.dart';
import 'pdf_exporter.dart';
import 'txt_exporter.dart';

class ExportResult {
  final Uint8List bytes;

  /// Nome sugerido no diálogo de salvar.
  final String fileName;

  const ExportResult({required this.bytes, required this.fileName});
}

/// Junta as três etapas da exportação: ler o projeto, montar o livro e
/// serializar no formato escolhido.
class ExportService {
  const ExportService();

  static const Map<ExportFormat, BookExporter> _exporters = {
    ExportFormat.epub: EpubExporter(),
    ExportFormat.docx: DocxExporter(),
    ExportFormat.pdf: PdfExporter(),
    ExportFormat.odt: OdtExporter(),
    ExportFormat.html: HtmlExporter(),
    ExportFormat.txt: TxtExporter(),
  };

  Future<ExportResult> export({
    required ProsaProject project,
    required ProjectTree tree,
    required ExportConfig config,
  }) async {
    final exporter = _exporters[config.format];
    if (exporter == null) {
      throw ExportException(
        'A exportação em ${config.format.label} ainda não está pronta.',
      );
    }
    if (config.selection.isEmpty) {
      throw const ExportException(
        'Escolha ao menos um capítulo ou apêndice para exportar.',
      );
    }

    BookCover? cover;
    final coverPath = config.coverPath;
    if (coverPath != null && config.format.supportsCover) {
      cover = await loadExportImage(coverPath);
    }

    final book = await const BookBuilder().build(
      projectPath: project.localPath,
      tree: tree,
      selection: config.selection,
      metadata: config.metadata,
      uuid: config.uuid,
      cover: cover,
    );

    if (book.isEmpty) {
      throw const ExportException(
        'Os arquivos escolhidos estão vazios — não há texto para exportar.',
      );
    }

    return ExportResult(
      bytes: await exporter.build(book),
      fileName: fileNameFor(config),
    );
  }

  static bool isAvailable(ExportFormat format) => _exporters.containsKey(format);

  static String fileNameFor(ExportConfig config) {
    final name = sanitizeFileName(config.metadata.title);
    return '${name.isEmpty ? 'livro' : name}.${config.format.extension}';
  }
}
