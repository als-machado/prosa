import 'dart:convert';
import 'dart:typed_data';

import '../domain/models/book.dart';
import '../domain/models/export_format.dart';
import 'book_exporter.dart';

/// Escreve o livro em texto puro.
///
/// Sem formatação nenhuma: negrito, itálico e link viram o texto que estava
/// escrito. As linhas não são quebradas em largura fixa de propósito — quem
/// abre um .txt quase sempre vai colar o texto em outro lugar, e uma quebra
/// dura no meio do parágrafo atrapalha mais do que ajuda.
class TxtExporter implements BookExporter {
  const TxtExporter();

  @override
  ExportFormat get format => ExportFormat.txt;

  @override
  Future<Uint8List> build(Book book, {DateTime? modified}) async {
    final out = StringBuffer();
    final metadata = book.metadata;

    if (metadata.title.isNotEmpty) out.writeln(metadata.title.toUpperCase());
    if (metadata.author.isNotEmpty) out.writeln(metadata.author);
    if (metadata.publisher.isNotEmpty) out.writeln(metadata.publisher);
    if (metadata.rights.isNotEmpty) out.writeln(metadata.rights);

    for (final walked in walkSections(book.sections)) {
      out.writeln();
      out.writeln();
      _writeTitle(out, walked.section.title, walked.depth);
      // Seção que só agrupa outras (o grupo "Personagens", por exemplo) não
      // ganha linha em branco sobrando embaixo do título.
      if (walked.section.blocks.isNotEmpty) {
        out.writeln();
        _writeBlocks(out, walked.section.blocks);
      }
    }

    return Uint8List.fromList(utf8.encode(out.toString()));
  }

  /// Título de capítulo sublinhado com `=`, de subseção com `-`. É a convenção
  /// de texto puro mais antiga que existe e a única que sobrevive a qualquer
  /// editor.
  void _writeTitle(StringBuffer out, String title, int depth) {
    out.writeln(title);
    final rule = switch (depth) {
      0 => '=',
      1 => '-',
      _ => null,
    };
    // runes e não length: com um emoji no título, o sublinhado sairia torto.
    if (rule != null) out.writeln(rule * title.runes.length);
  }

  void _writeBlocks(StringBuffer out, List<BookBlock> blocks, {int indent = 0}) {
    final prefix = '  ' * indent;
    var numbered = 0;

    for (final block in blocks) {
      if (block.type != BookBlockType.numberedItem) numbered = 0;

      switch (block.type) {
        case BookBlockType.heading:
          out.writeln();
          out.writeln('$prefix${block.plainText}');
          out.writeln();
        case BookBlockType.paragraph:
          out.writeln('$prefix${block.plainText}');
        case BookBlockType.quote:
          out.writeln('$prefix    ${block.plainText}');
        case BookBlockType.bulletedItem:
          out.writeln('$prefix- ${block.plainText}');
        case BookBlockType.numberedItem:
          numbered++;
          out.writeln('$prefix$numbered. ${block.plainText}');
        case BookBlockType.todoItem:
          out.writeln('$prefix[${block.checked ? 'x' : ' '}] ${block.plainText}');
        case BookBlockType.code:
          for (final line in block.plainText.split('\n')) {
            out.writeln('$prefix    $line');
          }
        case BookBlockType.divider:
          out.writeln();
          out.writeln('$prefix* * *');
          out.writeln();
        case BookBlockType.image:
          // Não há como mostrar a imagem; fica o registro de que havia uma.
          out.writeln('$prefix[imagem]');
        case BookBlockType.table:
          for (final row in block.tableRows) {
            out.writeln(
              '$prefix${row.map((cell) => cell.map((r) => r.text).join()).join(' | ')}',
            );
          }
      }

      if (block.children.isNotEmpty) {
        _writeBlocks(out, block.children, indent: indent + 1);
      }
    }
  }
}
