import 'dart:typed_data';

import 'book_metadata.dart';

/// Modelo intermediário entre os arquivos do projeto e os formatos de saída.
///
/// Existe para que EPUB, DOCX, PDF, ODT, HTML e TXT sejam serializações
/// diferentes da **mesma** leitura do projeto: quem lê o disco e resolve
/// título de capítulo, ordem e apêndices é o `BookBuilder`, uma vez só.

/// Trecho de texto com formatação uniforme.
class TextRun {
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final bool code;
  final String? href;

  const TextRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.code = false,
    this.href,
  });
}

enum BookBlockType {
  paragraph,
  heading,
  quote,
  bulletedItem,
  numberedItem,
  todoItem,
  code,
  divider,
  image,
  table,
}

class BookBlock {
  final BookBlockType type;
  final List<TextRun> runs;

  /// Nível do título, 1 a 6. Só vale para [BookBlockType.heading].
  final int level;

  /// Linguagem do bloco de código, quando declarada na cerca.
  final String? language;
  final bool checked;
  final String? imageUrl;

  /// Linhas × colunas × trechos. A primeira linha é o cabeçalho.
  final List<List<List<TextRun>>> tableRows;

  /// Blocos aninhados — item de lista dentro de item de lista.
  final List<BookBlock> children;

  /// Primeiro parágrafo depois de um título ou de uma quebra de cena: em
  /// livro ele não leva recuo de primeira linha.
  final bool startsBlock;

  const BookBlock({
    required this.type,
    this.runs = const [],
    this.level = 1,
    this.language,
    this.checked = false,
    this.imageUrl,
    this.tableRows = const [],
    this.children = const [],
    this.startsBlock = false,
  });

  String get plainText => runs.map((r) => r.text).join();

  bool get isBlank =>
      type == BookBlockType.paragraph &&
      children.isEmpty &&
      plainText.trim().isEmpty;

  BookBlock copyWith({int? level, bool? startsBlock, List<BookBlock>? children}) =>
      BookBlock(
        type: type,
        runs: runs,
        level: level ?? this.level,
        language: language,
        checked: checked,
        imageUrl: imageUrl,
        tableRows: tableRows,
        children: children ?? this.children,
        startsBlock: startsBlock ?? this.startsBlock,
      );
}

/// Uma parte do livro com título próprio: um capítulo, um grupo de apêndices,
/// um personagem dentro do grupo "Personagens".
///
/// A árvore é recursiva porque o sumário de um EPUB também é: grupo →
/// personagem → "Características". Cada seção de primeiro nível vira um
/// arquivo XHTML; as de dentro viram âncoras nele.
class BookSection {
  /// Identificador estável, usado como nome de arquivo e como âncora.
  final String id;
  final String title;
  final List<BookBlock> blocks;
  final List<BookSection> subsections;

  const BookSection({
    required this.id,
    required this.title,
    this.blocks = const [],
    this.subsections = const [],
  });

  bool get isEmpty =>
      blocks.every((b) => b.isBlank) && subsections.every((s) => s.isEmpty);
}

/// Imagem de capa já lida do disco e convertida para um formato que o
/// formato de saída aceita.
class BookCover {
  final Uint8List bytes;
  final String mediaType;
  final String extension;

  /// DOCX, ODT e PDF precisam do tamanho para reservar o espaço da imagem na
  /// página; no EPUB quem decide é o leitor.
  final int width;
  final int height;

  const BookCover({
    required this.bytes,
    required this.mediaType,
    required this.extension,
    this.width = 0,
    this.height = 0,
  });

  /// Proporção altura/largura, com 3:2 de retrato como padrão quando o
  /// tamanho não pôde ser lido.
  double get aspectRatio => (width > 0 && height > 0) ? height / width : 1.5;
}

class Book {
  final BookMetadata metadata;
  final BookCover? cover;
  final List<BookSection> chapters;
  final List<BookSection> appendices;

  /// Identificador único e estável do livro, guardado no projeto: reexportar
  /// o mesmo livro tem de gerar o mesmo identificador, senão a biblioteca do
  /// leitor passa a mostrar duas cópias.
  final String uuid;

  const Book({
    required this.metadata,
    required this.uuid,
    this.cover,
    this.chapters = const [],
    this.appendices = const [],
  });

  List<BookSection> get sections => [...chapters, ...appendices];

  bool get isEmpty => sections.isEmpty;
}

/// Uma seção da árvore junto com a profundidade em que ela está.
typedef WalkedSection = ({BookSection section, int depth});

/// Percorre a árvore de seções em profundidade.
///
/// Todo exportador precisa disto: a árvore só continua árvore no EPUB (um
/// arquivo por seção de primeiro nível) e no sumário; nos outros formatos o
/// livro é uma sequência de títulos com nível.
Iterable<WalkedSection> walkSections(
  List<BookSection> sections, [
  int depth = 0,
]) sync* {
  for (final section in sections) {
    yield (section: section, depth: depth);
    yield* walkSections(section.subsections, depth + 1);
  }
}
