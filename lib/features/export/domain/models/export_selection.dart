import '../../../projects/presentation/providers/project_tree_provider.dart';

/// O que entra no arquivo exportado.
///
/// Guarda **caminhos** e não índices: renomear ou criar um capítulo entre uma
/// exportação e outra não pode mudar silenciosamente o que vai ser exportado.
class ExportSelection {
  /// Diretórios dos capítulos incluídos, na ordem em que aparecem na árvore.
  final Set<String> chapters;

  /// Diretórios dos personagens incluídos como apêndice.
  final Set<String> characters;

  /// Arquivos .md de misc/ (notas, locais, pesquisa…) incluídos como apêndice.
  final Set<String> miscFiles;

  final bool synopsis;
  final bool glossary;

  const ExportSelection({
    this.chapters = const {},
    this.characters = const {},
    this.miscFiles = const {},
    this.synopsis = false,
    this.glossary = false,
  });

  /// Padrão de um projeto que nunca foi exportado: o livro inteiro, sem
  /// apêndices — material de apoio é do autor, não do leitor.
  factory ExportSelection.allChapters(ProjectTree tree) => ExportSelection(
        chapters: tree.chapters.map((c) => c.dirPath).toSet(),
      );

  bool get isEmpty =>
      chapters.isEmpty &&
      characters.isEmpty &&
      miscFiles.isEmpty &&
      !synopsis &&
      !glossary;

  bool get hasAppendices =>
      characters.isNotEmpty || miscFiles.isNotEmpty || synopsis || glossary;

  ExportSelection copyWith({
    Set<String>? chapters,
    Set<String>? characters,
    Set<String>? miscFiles,
    bool? synopsis,
    bool? glossary,
  }) =>
      ExportSelection(
        chapters: chapters ?? this.chapters,
        characters: characters ?? this.characters,
        miscFiles: miscFiles ?? this.miscFiles,
        synopsis: synopsis ?? this.synopsis,
        glossary: glossary ?? this.glossary,
      );

  Map<String, dynamic> toJson() => {
        'chapters': chapters.toList()..sort(),
        'characters': characters.toList()..sort(),
        'misc_files': miscFiles.toList()..sort(),
        'synopsis': synopsis,
        'glossary': glossary,
      };

  factory ExportSelection.fromJson(Map<String, dynamic> json) =>
      ExportSelection(
        chapters: (json['chapters'] as List?)?.cast<String>().toSet() ?? {},
        characters: (json['characters'] as List?)?.cast<String>().toSet() ?? {},
        miscFiles: (json['misc_files'] as List?)?.cast<String>().toSet() ?? {},
        synopsis: json['synopsis'] as bool? ?? false,
        glossary: json['glossary'] as bool? ?? false,
      );
}
