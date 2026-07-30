import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/models/book.dart';
import '../domain/models/export_format.dart';
import 'book_exporter.dart';

/// Diagrama o livro em PDF.
///
/// É o único formato em que a exportação decide onde cada linha cai — nos
/// outros quem pagina é o leitor ou o editor de texto. Daí as escolhas de
/// miolo estarem todas aqui: página de 15×22 cm, margem interna maior que a
/// externa, texto justificado com recuo de primeira linha, título de capítulo
/// abrindo página nova.
class PdfExporter implements BookExporter {
  const PdfExporter();

  @override
  ExportFormat get format => ExportFormat.pdf;

  /// Miolo de 15×22 cm — o formato mais comum de romance no Brasil.
  static const _pageFormat = PdfPageFormat(
    15 * PdfPageFormat.cm,
    22 * PdfPageFormat.cm,
    marginLeft: 2.0 * PdfPageFormat.cm,
    marginRight: 1.6 * PdfPageFormat.cm,
    marginTop: 1.8 * PdfPageFormat.cm,
    marginBottom: 1.8 * PdfPageFormat.cm,
  );

  static const _bodySize = 11.0;
  static const _lineSpacing = 3.4;
  static const _firstLineIndent = 14.0;

  @override
  Future<Uint8List> build(Book book, {DateTime? modified}) async {
    final fonts = await _BookFonts.load();
    final metadata = book.metadata;

    final document = pw.Document(
      pageMode: PdfPageMode.outlines,
      title: metadata.title.isEmpty ? null : metadata.title,
      author: metadata.author.isEmpty ? null : metadata.author,
      subject: metadata.description.isEmpty ? null : metadata.description,
      keywords: metadata.subjects.isEmpty ? null : metadata.subjects.join(', '),
      creator: 'Prosa',
      theme: pw.ThemeData.withFont(
        base: fonts.regular,
        bold: fonts.bold,
        italic: fonts.italic,
        boldItalic: fonts.boldItalic,
      ).copyWith(
        defaultTextStyle: pw.TextStyle(font: fonts.regular, fontSize: _bodySize),
      ),
    );

    final cover = book.cover;
    if (cover != null) {
      document.addPage(
        pw.Page(
          pageFormat: _pageFormat.copyWith(
            marginLeft: 0,
            marginRight: 0,
            marginTop: 0,
            marginBottom: 0,
          ),
          build: (context) => pw.Center(
            child: pw.Image(
              pw.MemoryImage(cover.bytes),
              fit: pw.BoxFit.contain,
            ),
          ),
        ),
      );
    }

    document.addPage(
      pw.Page(
        pageFormat: _pageFormat,
        build: (context) => _titlePage(book),
      ),
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: _pageFormat,
        // O padrão do pacote é 20 páginas — livro nenhum cabe nisso, e o
        // excedente sairia truncado sem aviso.
        maxPages: 5000,
        footer: _footer,
        build: (context) => _tableOfContents(book),
      ),
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: _pageFormat,
        maxPages: 5000,
        footer: _footer,
        build: (context) => [
          for (final walked in walkSections(book.sections))
            ..._section(walked, fonts),
        ],
      ),
    );

    return document.save();
  }

  // ------------------------------------------------------------------ página

  pw.Widget _titlePage(Book book) {
    final metadata = book.metadata;
    return pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          metadata.title,
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 26),
        ),
        if (metadata.author.isNotEmpty) ...[
          pw.SizedBox(height: 18),
          pw.Text(metadata.author, style: const pw.TextStyle(fontSize: 14)),
        ],
        pw.Spacer(),
        if (metadata.publisher.isNotEmpty)
          pw.Text(metadata.publisher, style: const pw.TextStyle(fontSize: 9)),
        if (metadata.rights.isNotEmpty)
          pw.Text(metadata.rights, style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  /// Sumário com link para cada seção, sem número de página.
  ///
  /// O número exigiria diagramar o livro inteiro antes de montar o sumário e
  /// depois refazer as contas — e o leitor de PDF já tem os marcadores, que
  /// saem daqui pelo [pw.Outline] de cada título.
  List<pw.Widget> _tableOfContents(Book book) {
    return [
      pw.Header(level: 0, text: 'Sumário'),
      pw.SizedBox(height: 8),
      for (final walked in walkSections(book.sections))
        pw.Padding(
          padding: pw.EdgeInsets.only(
            left: walked.depth * 14.0,
            bottom: 4,
          ),
          child: pw.Link(
            destination: walked.section.id,
            child: pw.Text(
              walked.section.title,
              style: pw.TextStyle(
                fontSize: walked.depth == 0 ? _bodySize : _bodySize - 1,
                color: walked.depth == 0 ? null : PdfColors.grey700,
              ),
            ),
          ),
        ),
    ];
  }

  pw.Widget _footer(pw.Context context) => pw.Container(
        alignment: pw.Alignment.center,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text(
          '${context.pageNumber}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      );

  List<pw.Widget> _section(WalkedSection walked, _BookFonts fonts) {
    final titleSize = switch (walked.depth) {
      0 => 18.0,
      1 => 14.0,
      _ => 12.0,
    };

    return [
      // O Outline é o que vira marcador no leitor de PDF e destino do link do
      // sumário; o `name` tem de bater com o destination lá.
      pw.Outline(
        name: walked.section.id,
        title: walked.section.title,
        level: walked.depth,
        child: pw.Container(
          width: double.infinity,
          margin: pw.EdgeInsets.only(
            top: walked.depth == 0 ? 28 : 20,
            bottom: walked.depth == 0 ? 20 : 12,
          ),
          child: pw.Text(
            walked.section.title,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: fonts.regular, fontSize: titleSize),
          ),
        ),
      ),
      ..._blocks(walked.section.blocks, fonts),
    ];
  }

  List<pw.Widget> _blocks(
    List<BookBlock> blocks,
    _BookFonts fonts, {
    int indent = 0,
  }) {
    final widgets = <pw.Widget>[];
    var numbered = 0;

    for (final block in blocks) {
      if (block.type != BookBlockType.numberedItem) numbered = 0;

      switch (block.type) {
        case BookBlockType.heading:
          widgets.add(
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(top: 14, bottom: 8),
              child: pw.Text(
                block.plainText,
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: _bodySize + (6 - block.level).clamp(0, 4),
                ),
              ),
            ),
          );

        case BookBlockType.paragraph:
          widgets.add(_paragraph(block, fonts, indent: indent));

        case BookBlockType.quote:
          widgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.symmetric(vertical: 6),
              padding: const pw.EdgeInsets.only(left: 18, right: 18),
              child: pw.RichText(
                textAlign: pw.TextAlign.justify,
                text: pw.TextSpan(
                  style: pw.TextStyle(
                    font: fonts.italic,
                    fontSize: _bodySize,
                    lineSpacing: _lineSpacing,
                  ),
                  children: _spans(block.runs, fonts, italic: true),
                ),
              ),
            ),
          );

        case BookBlockType.bulletedItem:
          widgets.add(_listItem('•', block, fonts, indent));
        case BookBlockType.numberedItem:
          numbered++;
          widgets.add(_listItem('$numbered.', block, fonts, indent));
        case BookBlockType.todoItem:
          widgets.add(
            _listItem(block.checked ? '[x]' : '[ ]', block, fonts, indent),
          );

        case BookBlockType.code:
          widgets.add(
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.symmetric(vertical: 8),
              padding: const pw.EdgeInsets.all(8),
              color: PdfColors.grey200,
              child: pw.Text(
                block.plainText,
                style: pw.TextStyle(
                  font: fonts.mono,
                  // A Courier do próprio PDF só tem Latin-1. Sem a reserva,
                  // um acento dentro do bloco de código derrubaria a
                  // exportação inteira.
                  fontFallback: [fonts.regular],
                  fontSize: _bodySize - 1.5,
                ),
              ),
            ),
          );

        case BookBlockType.divider:
          widgets.add(
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.symmetric(vertical: 12),
              child: pw.Text(
                '* * *',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: _bodySize, letterSpacing: 4),
              ),
            ),
          );

        case BookBlockType.image:
          // Só a capa é embutida; ver a mesma decisão nos outros formatos.
          break;

        case BookBlockType.table:
          widgets.add(_table(block, fonts));
      }

      if (block.children.isNotEmpty) {
        widgets.addAll(_blocks(block.children, fonts, indent: indent + 1));
      }
    }

    return widgets;
  }

  pw.Widget _paragraph(BookBlock block, _BookFonts fonts, {int indent = 0}) {
    return pw.Container(
      padding: pw.EdgeInsets.only(left: indent * 14.0),
      child: pw.RichText(
        textAlign: pw.TextAlign.justify,
        text: pw.TextSpan(
          style: pw.TextStyle(
            font: fonts.regular,
            fontSize: _bodySize,
            lineSpacing: _lineSpacing,
          ),
          children: [
            // Recuo de primeira linha: o widget de texto não tem `text-indent`,
            // então o recuo entra como um espaço de largura fixa antes da
            // primeira palavra.
            if (!block.startsBlock)
              pw.WidgetSpan(
                child: pw.SizedBox(width: _firstLineIndent, height: 1),
              ),
            ..._spans(block.runs, fonts),
          ],
        ),
      ),
    );
  }

  pw.Widget _listItem(
    String marker,
    BookBlock block,
    _BookFonts fonts,
    int indent,
  ) {
    return pw.Container(
      margin: pw.EdgeInsets.only(left: 12 + indent * 14.0, bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 18,
            child: pw.Text(marker, style: const pw.TextStyle(fontSize: _bodySize)),
          ),
          pw.Expanded(
            child: pw.RichText(
              text: pw.TextSpan(
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: _bodySize,
                  lineSpacing: 1.5,
                ),
                children: _spans(block.runs, fonts),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _table(BookBlock block, _BookFonts fonts) {
    if (block.tableRows.isEmpty) return pw.SizedBox();

    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 10),
      child: pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
        children: [
          for (var row = 0; row < block.tableRows.length; row++)
            pw.TableRow(
              children: [
                for (final cell in block.tableRows[row])
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(
                      cell.map((r) => r.text).join(),
                      style: pw.TextStyle(
                        font: row == 0 ? fonts.bold : fonts.regular,
                        fontSize: _bodySize - 1.5,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  List<pw.InlineSpan> _spans(
    List<TextRun> runs,
    _BookFonts fonts, {
    bool italic = false,
  }) {
    return [
      for (final run in runs)
        pw.TextSpan(
          text: run.text,
          style: pw.TextStyle(
            font: fonts.pick(
              bold: run.bold,
              italic: run.italic || italic,
              mono: run.code,
            ),
            decoration: run.strikethrough
                ? pw.TextDecoration.lineThrough
                : (run.underline || run.href != null
                    ? pw.TextDecoration.underline
                    : null),
            color: run.href != null ? PdfColors.blue800 : null,
          ),
        ),
    ];
  }
}

/// As fontes do miolo.
///
/// O PDF **precisa** da fonte dentro do arquivo. As fontes internas do formato
/// (Times, Helvetica) só enxergam Latin-1, o que deixaria de fora travessão,
/// aspas curvas e reticências — a pontuação de diálogo em português. Por isso
/// a Liberation Serif vai embutida em `assets/fonts`.
class _BookFonts {
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font italic;
  final pw.Font boldItalic;

  _BookFonts({
    required this.regular,
    required this.bold,
    required this.italic,
    required this.boldItalic,
  });

  pw.Font? _mono;

  /// Courier só é criada se houver bloco de código: o pacote avisa em log que
  /// ela não tem Unicode, e livro nenhum precisa ouvir isso à toa.
  pw.Font get mono => _mono ??= pw.Font.courier();

  static _BookFonts? _cached;

  /// Carregar quatro TTF custa alguns megabytes e algumas centenas de
  /// milissegundos; exportar duas vezes seguidas não deve pagar isso de novo.
  static Future<_BookFonts> load() async {
    final cached = _cached;
    if (cached != null) return cached;

    Future<pw.Font> ttf(String name) async =>
        pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));

    final fonts = _BookFonts(
      regular: await ttf('LiberationSerif-Regular'),
      bold: await ttf('LiberationSerif-Bold'),
      italic: await ttf('LiberationSerif-Italic'),
      boldItalic: await ttf('LiberationSerif-BoldItalic'),
    );
    return _cached = fonts;
  }

  pw.Font pick({bool bold = false, bool italic = false, bool mono = false}) {
    if (mono) return this.mono;
    if (bold && italic) return boldItalic;
    if (bold) return this.bold;
    if (italic) return this.italic;
    return regular;
  }
}
