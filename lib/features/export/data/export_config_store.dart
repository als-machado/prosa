import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../projects/presentation/providers/project_tree_provider.dart';
import '../../../shared/models/prosa_project.dart';
import '../domain/models/book_metadata.dart';
import '../domain/models/export_format.dart';
import '../domain/models/export_selection.dart';

/// O que o autor escolheu da última vez que exportou.
class ExportConfig {
  final ExportFormat format;
  final BookMetadata metadata;
  final ExportSelection selection;

  /// Caminho da imagem de capa. Relativo quando a imagem mora dentro do
  /// projeto, para que o arquivo continue válido em outra máquina.
  final String? coverPath;

  /// Identificador do livro, gerado uma vez e nunca mais.
  final String uuid;

  const ExportConfig({
    required this.format,
    required this.metadata,
    required this.selection,
    required this.uuid,
    this.coverPath,
  });

  ExportConfig copyWith({
    ExportFormat? format,
    BookMetadata? metadata,
    ExportSelection? selection,
    String? coverPath,
    bool clearCover = false,
  }) =>
      ExportConfig(
        format: format ?? this.format,
        metadata: metadata ?? this.metadata,
        selection: selection ?? this.selection,
        uuid: uuid,
        coverPath: clearCover ? null : (coverPath ?? this.coverPath),
      );
}

/// Guarda a configuração de exportação junto do livro, em `.prosa_export`.
///
/// Fica no projeto e não nas preferências do app porque é do livro: ISBN,
/// editora e capa acompanham o texto quando ele vai para outro computador
/// pelo Git. Sem isso o autor redigitaria tudo a cada exportação.
class ExportConfigStore {
  const ExportConfigStore();

  static const _uuid = Uuid();

  Future<ExportConfig> load(ProsaProject project, ProjectTree tree) async {
    final file = File('${project.localPath}/${AppConstants.exportConfigFile}');

    if (await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final selection = ExportSelection.fromJson(
          (json['selection'] as Map?)?.cast<String, dynamic>() ?? {},
        );

        // Capítulo escrito depois da última exportação entra marcado. Guardar
        // só os incluídos não bastaria para saber a diferença entre "capítulo
        // novo" e "capítulo que o autor tirou do livro de propósito".
        final known =
            (json['known_chapters'] as List?)?.cast<String>().toSet() ??
                const <String>{};
        final fresh = tree.chapters
            .map((c) => c.dirPath)
            .where((path) => !known.contains(path));

        return ExportConfig(
          format: ExportFormat.fromName(json['format'] as String?),
          metadata: BookMetadata.fromJson(
            (json['metadata'] as Map?)?.cast<String, dynamic>() ?? {},
          ),
          selection:
              selection.copyWith(chapters: {...selection.chapters, ...fresh}),
          uuid: json['uuid'] as String? ?? _uuid.v4(),
          coverPath: _absoluteCover(project.localPath, json['cover'] as String?),
        );
      } catch (_) {
        // Arquivo corrompido não pode impedir a exportação: cai no padrão.
      }
    }

    return ExportConfig(
      format: ExportFormat.epub,
      metadata: BookMetadata.fromProject(project),
      selection: ExportSelection.allChapters(tree),
      uuid: _uuid.v4(),
    );
  }

  Future<void> save(
    ProsaProject project,
    ExportConfig config,
    ProjectTree tree,
  ) async {
    final file = File('${project.localPath}/${AppConstants.exportConfigFile}');
    final json = <String, dynamic>{
      'format': config.format.name,
      'uuid': config.uuid,
      'metadata': config.metadata.toJson(),
      'selection': config.selection.toJson(),
      'known_chapters': tree.chapters.map((c) => c.dirPath).toList()..sort(),
      if (config.coverPath != null)
        'cover': _relativeCover(project.localPath, config.coverPath!),
    };
    await file.writeAsString('${const JsonEncoder.withIndent('  ').convert(json)}\n');
  }

  String? _absoluteCover(String projectPath, String? stored) {
    if (stored == null || stored.isEmpty) return null;
    return stored.startsWith('/') ? stored : '$projectPath/$stored';
  }

  String _relativeCover(String projectPath, String path) =>
      path.startsWith('$projectPath/')
          ? path.substring(projectPath.length + 1)
          : path;
}
