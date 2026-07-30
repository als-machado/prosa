import 'package:appflowy_editor/appflowy_editor.dart';

import '../../editor/domain/code_block.dart';
import 'models/book.dart';

/// Traduz o documento do editor para os blocos do livro.
///
/// A leitura do Markdown é a **mesma** do editor (`markdownToEditorDocument`),
/// de propósito: o arquivo salvo pelo Prosa tem uma linha por bloco, e um
/// parser de Markdown comum juntaria parágrafos seguidos num só e comeria as
/// linhas em branco. Exportar por outro caminho daria um livro diferente do
/// que o autor vê na tela.
List<BookBlock> documentToBookBlocks(Document document) =>
    document.root.children.map(_convertNode).nonNulls.toList();

BookBlock? _convertNode(Node node) {
  switch (node.type) {
    case HeadingBlockKeys.type:
      final level = node.attributes[HeadingBlockKeys.level];
      return BookBlock(
        type: BookBlockType.heading,
        runs: _runs(node.delta),
        level: level is int ? level.clamp(1, 6) : 1,
      );

    case QuoteBlockKeys.type:
      return BookBlock(
        type: BookBlockType.quote,
        runs: _runs(node.delta),
        children: _children(node),
      );

    case BulletedListBlockKeys.type:
      return BookBlock(
        type: BookBlockType.bulletedItem,
        runs: _runs(node.delta),
        children: _children(node),
      );

    case NumberedListBlockKeys.type:
      return BookBlock(
        type: BookBlockType.numberedItem,
        runs: _runs(node.delta),
        children: _children(node),
      );

    case TodoListBlockKeys.type:
      return BookBlock(
        type: BookBlockType.todoItem,
        runs: _runs(node.delta),
        checked: node.attributes[TodoListBlockKeys.checked] == true,
        children: _children(node),
      );

    case CodeBlockKeys.type:
      return BookBlock(
        type: BookBlockType.code,
        runs: _runs(node.delta),
        language: node.attributes[CodeBlockKeys.language] as String?,
      );

    case DividerBlockKeys.type:
      return const BookBlock(type: BookBlockType.divider);

    case ImageBlockKeys.type:
      final url = node.attributes[ImageBlockKeys.url] as String?;
      if (url == null || url.isEmpty) return null;
      return BookBlock(type: BookBlockType.image, imageUrl: url);

    case TableBlockKeys.type:
      return _convertTable(node);

    default:
      // Inclui o parágrafo e qualquer bloco que a biblioteca ganhe depois:
      // texto solto é melhor que bloco sumido.
      return BookBlock(
        type: BookBlockType.paragraph,
        runs: _runs(node.delta),
        children: _children(node),
      );
  }
}

List<BookBlock> _children(Node node) =>
    node.children.map(_convertNode).nonNulls.toList();

/// As células vêm como filhas soltas do nó da tabela, cada uma sabendo sua
/// linha e coluna; aqui elas voltam a ser uma grade.
BookBlock? _convertTable(Node node) {
  final colsLen = node.attributes[TableBlockKeys.colsLen];
  final rowsLen = node.attributes[TableBlockKeys.rowsLen];
  if (colsLen is! int || rowsLen is! int || colsLen <= 0 || rowsLen <= 0) {
    return null;
  }

  final grid = <List<List<TextRun>>>[];
  for (var row = 0; row < rowsLen; row++) {
    final cells = <List<TextRun>>[];
    for (var col = 0; col < colsLen; col++) {
      final matches = node.children.where(
        (cell) =>
            cell.attributes[TableCellBlockKeys.colPosition] == col &&
            cell.attributes[TableCellBlockKeys.rowPosition] == row,
      );
      cells.add(
        matches.isEmpty
            ? const []
            : matches.first.children.expand((n) => _runs(n.delta)).toList(),
      );
    }
    grid.add(cells);
  }
  return BookBlock(type: BookBlockType.table, tableRows: grid);
}

List<TextRun> _runs(Delta? delta) {
  if (delta == null) return const [];
  final runs = <TextRun>[];
  for (final op in delta) {
    if (op is! TextInsert) continue;
    final attributes = op.attributes ?? const <String, dynamic>{};
    final href = attributes[AppFlowyRichTextKeys.href];
    runs.add(
      TextRun(
        op.text,
        bold: attributes[AppFlowyRichTextKeys.bold] == true,
        italic: attributes[AppFlowyRichTextKeys.italic] == true,
        underline: attributes[AppFlowyRichTextKeys.underline] == true,
        strikethrough: attributes[AppFlowyRichTextKeys.strikethrough] == true,
        code: attributes[AppFlowyRichTextKeys.code] == true,
        href: href is String && href.isNotEmpty ? href : null,
      ),
    );
  }
  return runs;
}
