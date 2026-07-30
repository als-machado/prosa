import '../domain/models/book.dart';

/// Converte blocos do livro em XHTML.
///
/// XHTML e não HTML solto: o conteúdo de um EPUB é lido por um parser de XML,
/// que morre em tag não fechada. O mesmo resultado serve para a exportação em
/// HTML, que é a mesma marcação dentro de uma página só.
class XhtmlRenderer {
  /// Caminho absoluto da imagem no disco → caminho dela dentro do pacote.
  /// Imagem que não estiver aqui e não for http(s) é ignorada: melhor um
  /// livro sem a figura do que um arquivo que o leitor recusa a abrir.
  final Map<String, String> imageHrefs;

  const XhtmlRenderer({this.imageHrefs = const {}});

  String renderBlocks(List<BookBlock> blocks) {
    final out = StringBuffer();
    var i = 0;
    while (i < blocks.length) {
      final block = blocks[i];

      // Itens de lista seguidos viram uma lista só.
      if (_listTag(block.type) != null) {
        final group = <BookBlock>[];
        while (i < blocks.length && blocks[i].type == block.type) {
          group.add(blocks[i]);
          i++;
        }
        out.writeln(_renderList(block.type, group));
        continue;
      }

      final rendered = _renderBlock(block);
      if (rendered != null) out.writeln(rendered);
      i++;
    }
    return out.toString();
  }

  String? _renderBlock(BookBlock block) {
    switch (block.type) {
      case BookBlockType.heading:
        final level = block.level.clamp(1, 6);
        return '<h$level>${renderRuns(block.runs)}</h$level>';

      case BookBlockType.paragraph:
        final css = block.startsBlock ? ' class="first"' : '';
        return '<p$css>${renderRuns(block.runs)}</p>';

      case BookBlockType.quote:
        final inner = StringBuffer('<p>${renderRuns(block.runs)}</p>');
        if (block.children.isNotEmpty) inner.write(renderBlocks(block.children));
        return '<blockquote>$inner</blockquote>';

      case BookBlockType.code:
        final language = block.language;
        final css = (language == null || language.isEmpty)
            ? ''
            : ' class="language-${escape(language)}"';
        return '<pre><code$css>${escape(block.plainText)}</code></pre>';

      // Quebra de cena. Um <hr> seria o equivalente semântico, mas leitor
      // nenhum concorda em como desenhá-lo — os três asteriscos centrados são
      // a convenção do livro impresso e saem iguais em todo lugar.
      case BookBlockType.divider:
        return '<p class="scene">* * *</p>';

      case BookBlockType.image:
        final href = _imageHref(block.imageUrl);
        if (href == null) return null;
        return '<div class="image"><img src="${escape(href)}" alt=""/></div>';

      case BookBlockType.table:
        return _renderTable(block);

      case BookBlockType.bulletedItem:
      case BookBlockType.numberedItem:
      case BookBlockType.todoItem:
        return _renderList(block.type, [block]);
    }
  }

  String? _imageHref(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return imageHrefs[url];
  }

  String? _listTag(BookBlockType type) => switch (type) {
        BookBlockType.bulletedItem => 'ul',
        BookBlockType.numberedItem => 'ol',
        BookBlockType.todoItem => 'ul',
        _ => null,
      };

  String _renderList(BookBlockType type, List<BookBlock> items) {
    final tag = _listTag(type) ?? 'ul';
    final css = type == BookBlockType.todoItem ? ' class="todo"' : '';
    final out = StringBuffer('<$tag$css>\n');
    for (final item in items) {
      final marker = switch (type) {
        BookBlockType.todoItem => item.checked ? '☑ ' : '☐ ',
        _ => '',
      };
      out.write('<li>$marker${renderRuns(item.runs)}');
      if (item.children.isNotEmpty) {
        out.write('\n${renderBlocks(item.children)}');
      }
      out.writeln('</li>');
    }
    out.write('</$tag>');
    return out.toString();
  }

  String _renderTable(BookBlock block) {
    if (block.tableRows.isEmpty) return '';
    final out = StringBuffer('<table>\n');

    final header = block.tableRows.first;
    out.write('<thead>\n<tr>');
    for (final cell in header) {
      out.write('<th>${renderRuns(cell)}</th>');
    }
    out.writeln('</tr>\n</thead>');

    if (block.tableRows.length > 1) {
      out.writeln('<tbody>');
      for (final row in block.tableRows.skip(1)) {
        out.write('<tr>');
        for (final cell in row) {
          out.write('<td>${renderRuns(cell)}</td>');
        }
        out.writeln('</tr>');
      }
      out.writeln('</tbody>');
    }

    out.write('</table>');
    return out.toString();
  }

  String renderRuns(List<TextRun> runs) {
    final out = StringBuffer();
    for (final run in runs) {
      var html = escape(run.text);
      // Ordem de dentro para fora; o link fica por último para envolver
      // toda a formatação do trecho.
      if (run.code) html = '<code>$html</code>';
      if (run.bold) html = '<strong>$html</strong>';
      if (run.italic) html = '<em>$html</em>';
      if (run.strikethrough) html = '<s>$html</s>';
      if (run.underline) html = '<u>$html</u>';
      final href = run.href;
      if (href != null) html = '<a href="${escape(href)}">$html</a>';
      out.write(html);
    }
    return out.toString();
  }
}

/// O `&` vem primeiro, senão as entidades geradas pelas trocas seguintes
/// seriam escapadas de novo.
String escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
