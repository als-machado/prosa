import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../domain/models/book.dart';
import '../domain/models/export_format.dart';
import 'book_exporter.dart';
import 'xhtml_renderer.dart' show escape;

/// Escreve o livro em ODT (OpenDocument Text), o formato do LibreOffice.
///
/// Como o EPUB, é um ZIP que começa por um `mimetype` sem compressão. O que
/// muda é o miolo: aqui o texto é uma sequência de `text:h` e `text:p` com
/// estilos declarados em `styles.xml`.
class OdtExporter implements BookExporter {
  const OdtExporter();

  @override
  ExportFormat get format => ExportFormat.odt;

  @override
  Future<Uint8List> build(Book book, {DateTime? modified}) async {
    final archive = Archive();

    final mimetype = utf8.encode(ExportFormat.odt.mimeType);
    archive.add(ArchiveFile.noCompress('mimetype', mimetype.length, mimetype));

    final cover = book.cover;
    final coverPath = cover == null ? null : 'Pictures/cover.${cover.extension}';
    if (cover != null && coverPath != null) {
      archive.add(ArchiveFile.bytes(coverPath, cover.bytes));
    }

    archive
      ..add(
        ArchiveFile.string(
          'META-INF/manifest.xml',
          _manifest(cover, coverPath),
        ),
      )
      ..add(ArchiveFile.string('content.xml', _content(book, coverPath)))
      ..add(ArchiveFile.string('styles.xml', _styles))
      ..add(
        ArchiveFile.string('meta.xml', _meta(book, modified ?? DateTime.now())),
      );

    return ZipEncoder().encodeBytes(archive);
  }

  // ---------------------------------------------------------------- conteúdo

  String _content(Book book, String? coverPath) {
    final metadata = book.metadata;
    final out = StringBuffer();

    if (coverPath != null && book.cover != null) {
      out.write(_coverFrame(book.cover!, coverPath));
    }

    out.write(_paragraph('BookTitle', [TextRun(metadata.title)]));
    if (metadata.author.isNotEmpty) {
      out.write(_paragraph('BookAuthor', [TextRun(metadata.author)]));
    }
    if (metadata.publisher.isNotEmpty) {
      out.write(_paragraph('BookMeta', [TextRun(metadata.publisher)]));
    }
    if (metadata.rights.isNotEmpty) {
      out.write(_paragraph('BookMeta', [TextRun(metadata.rights)]));
    }

    out.write(
      '<text:h text:style-name="Chapter" text:outline-level="1">Sumário</text:h>',
    );
    for (final walked in walkSections(book.sections)) {
      // Tabulação e não espaços: o LibreOffice junta espaços seguidos, e a
      // hierarquia do sumário sumiria.
      final indent = '<text:tab/>' * walked.depth;
      out.write(
        '<text:p text:style-name="TocEntry">$indent'
        '<text:a xlink:type="simple" xlink:href="#${walked.section.id}">'
        '${escape(walked.section.title)}</text:a></text:p>',
      );
    }

    for (final walked in walkSections(book.sections)) {
      final level = (walked.depth + 1).clamp(1, 6);
      final style = walked.depth == 0 ? 'Chapter' : 'Section';
      out.write(
        '<text:h text:style-name="$style" text:outline-level="$level">'
        '<text:bookmark text:name="${walked.section.id}"/>'
        '${escape(walked.section.title)}</text:h>',
      );
      out.write(_blocks(walked.section.blocks));
    }

    return '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-content $_namespaces office:version="1.3">
<office:automatic-styles>
<style:style style:name="CoverFrame" style:family="graphic">
<style:graphic-properties style:vertical-pos="top" style:horizontal-pos="center" fo:margin-bottom="0.5cm"/>
</style:style>
</office:automatic-styles>
<office:body><office:text>
$out</office:text></office:body>
</office:document-content>
''';
  }

  String _blocks(List<BookBlock> blocks, {int indent = 0}) {
    final out = StringBuffer();
    var numbered = 0;

    for (final block in blocks) {
      if (block.type != BookBlockType.numberedItem) numbered = 0;

      switch (block.type) {
        case BookBlockType.heading:
          final level = block.level.clamp(1, 6);
          out.write(
            '<text:h text:style-name="Section" text:outline-level="$level">'
            '${_runs(block.runs)}</text:h>',
          );
        case BookBlockType.paragraph:
          out.write(
            _paragraph(block.startsBlock ? 'BodyFirst' : 'Body', block.runs),
          );
        case BookBlockType.quote:
          out.write(_paragraph('Quotation', block.runs));
        case BookBlockType.bulletedItem:
          out.write(_listItem('•', block.runs, indent));
        case BookBlockType.numberedItem:
          numbered++;
          out.write(_listItem('$numbered.', block.runs, indent));
        case BookBlockType.todoItem:
          out.write(_listItem(block.checked ? '☑' : '☐', block.runs, indent));
        case BookBlockType.code:
          out.write(_codeParagraph(block.plainText));
        case BookBlockType.divider:
          out.write(_paragraph('SceneBreak', const [TextRun('* * *')]));
        case BookBlockType.image:
          // Só a capa é embutida — ver a mesma decisão no DocxExporter.
          break;
        case BookBlockType.table:
          out.write(_table(block));
      }

      if (block.children.isNotEmpty) {
        out.write(_blocks(block.children, indent: indent + 1));
      }
    }
    return out.toString();
  }

  /// Marcador escrito na mão em vez de `text:list`, pela mesma razão do DOCX:
  /// lista de verdade exigiria uma definição de estilo por nível e por tipo,
  /// e o resultado na tela é o mesmo.
  String _listItem(String marker, List<TextRun> runs, int indent) {
    final style = indent == 0 ? 'ListItem' : 'ListItemNested';
    return '<text:p text:style-name="$style">$marker<text:tab/>'
        '${_runs(runs)}</text:p>';
  }

  String _codeParagraph(String code) {
    final lines = code.split('\n').map(escape).join('<text:line-break/>');
    return '<text:p text:style-name="CodeBlock">$lines</text:p>';
  }

  String _table(BookBlock block) {
    if (block.tableRows.isEmpty) return '';
    final columns = block.tableRows.first.length;
    final out = StringBuffer(
      '<table:table table:name="Tabela">'
      '<table:table-column table:number-columns-repeated="$columns"/>',
    );

    for (var row = 0; row < block.tableRows.length; row++) {
      out.write('<table:table-row>');
      for (final cell in block.tableRows[row]) {
        out.write(
          '<table:table-cell office:value-type="string">'
          '${_paragraph(row == 0 ? 'TableHeader' : 'TableCell', cell)}'
          '</table:table-cell>',
        );
      }
      out.write('</table:table-row>');
    }

    out.write('</table:table>');
    return out.toString();
  }

  String _coverFrame(BookCover cover, String path) {
    // Largura útil da A4 com margem de 2,5 cm.
    var width = 16.0;
    var height = width * cover.aspectRatio;
    if (height > 24.0) {
      height = 24.0;
      width = height / cover.aspectRatio;
    }
    final w = width.toStringAsFixed(2);
    final h = height.toStringAsFixed(2);

    return '<text:p text:style-name="Cover">'
        '<draw:frame draw:style-name="CoverFrame" draw:name="Capa" '
        'text:anchor-type="as-char" svg:width="${w}cm" svg:height="${h}cm">'
        '<draw:image xlink:href="${escape(path)}" xlink:type="simple" '
        'xlink:show="embed" xlink:actuate="onLoad"/>'
        '</draw:frame></text:p>';
  }

  String _paragraph(String style, List<TextRun> runs) =>
      '<text:p text:style-name="$style">${_runs(runs)}</text:p>';

  String _runs(List<TextRun> runs) {
    final out = StringBuffer();
    for (final run in runs) {
      var text = escape(run.text);

      // Estilos aninhados se somam: o de dentro só muda o que ele declara.
      if (run.code) text = '<text:span text:style-name="Code">$text</text:span>';
      if (run.bold) text = '<text:span text:style-name="Bold">$text</text:span>';
      if (run.italic) {
        text = '<text:span text:style-name="Italic">$text</text:span>';
      }
      if (run.strikethrough) {
        text = '<text:span text:style-name="Strike">$text</text:span>';
      }
      if (run.underline) {
        text = '<text:span text:style-name="Underline">$text</text:span>';
      }

      final href = run.href;
      if (href != null) {
        text = '<text:a xlink:type="simple" xlink:href="${escape(href)}">'
            '$text</text:a>';
      }
      out.write(text);
    }
    return out.toString();
  }

  // ------------------------------------------------------------------ partes

  String _manifest(BookCover? cover, String? coverPath) {
    final image = (cover == null || coverPath == null)
        ? ''
        : '<manifest:file-entry manifest:full-path="$coverPath" '
            'manifest:media-type="${cover.mediaType}"/>';
    return '''<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.3">
<manifest:file-entry manifest:full-path="/" manifest:media-type="${ExportFormat.odt.mimeType}"/>
<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
<manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
<manifest:file-entry manifest:full-path="meta.xml" manifest:media-type="text/xml"/>
$image
</manifest:manifest>
''';
  }

  String _meta(Book book, DateTime modified) {
    final metadata = book.metadata;
    final out = StringBuffer()
      ..writeln('<meta:generator>Prosa</meta:generator>')
      ..writeln('<dc:title>${escape(metadata.title)}</dc:title>');
    if (metadata.author.isNotEmpty) {
      out
        ..writeln('<dc:creator>${escape(metadata.author)}</dc:creator>')
        ..writeln(
          '<meta:initial-creator>${escape(metadata.author)}</meta:initial-creator>',
        );
    }
    if (metadata.description.isNotEmpty) {
      out.writeln('<dc:description>${escape(metadata.description)}</dc:description>');
    }
    if (metadata.language.isNotEmpty) {
      out.writeln('<dc:language>${escape(metadata.language)}</dc:language>');
    }
    for (final subject in metadata.subjects) {
      out.writeln('<meta:keyword>${escape(subject)}</meta:keyword>');
    }
    out.writeln('<dc:date>${_timestamp(modified)}</dc:date>');

    return '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-meta xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0" office:version="1.3">
<office:meta>
$out</office:meta>
</office:document-meta>
''';
  }

  static String _timestamp(DateTime dateTime) {
    final utc = dateTime.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)}'
        'T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}';
  }

  static const _namespaces =
      'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
      'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
      'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
      'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
      'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" '
      'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" '
      'xmlns:xlink="http://www.w3.org/1999/xlink" '
      'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"';

  static const _styles = '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles $_namespaces office:version="1.3">
<office:styles>

<style:style style:name="Standard" style:family="paragraph">
<style:paragraph-properties fo:text-align="justify" fo:line-height="150%" fo:orphans="2" fo:widows="2"/>
<style:text-properties style:font-name="Liberation Serif" fo:font-size="12pt"/>
</style:style>

<style:style style:name="Body" style:family="paragraph" style:parent-style-name="Standard">
<style:paragraph-properties fo:text-indent="1.25cm"/>
</style:style>

<style:style style:name="BodyFirst" style:family="paragraph" style:parent-style-name="Standard">
<style:paragraph-properties fo:text-indent="0cm"/>
</style:style>

<style:style style:name="Chapter" style:family="paragraph" style:parent-style-name="Standard">
<style:paragraph-properties fo:text-align="center" fo:break-before="page"
 fo:margin-top="2cm" fo:margin-bottom="1cm" fo:line-height="120%" fo:keep-with-next="always"/>
<style:text-properties fo:font-size="20pt"/>
</style:style>

<style:style style:name="Section" style:family="paragraph" style:parent-style-name="Standard">
<style:paragraph-properties fo:text-align="center"
 fo:margin-top="1cm" fo:margin-bottom="0.5cm" fo:line-height="120%" fo:keep-with-next="always"/>
<style:text-properties fo:font-size="15pt"/>
</style:style>

<style:style style:name="BookTitle" style:family="paragraph" style:parent-style-name="Standard">
<style:paragraph-properties fo:text-align="center" fo:margin-top="4cm" fo:margin-bottom="1cm" fo:line-height="120%"/>
<style:text-properties fo:font-size="28pt"/>
</style:style>

<style:style style:name="BookAuthor" style:family="paragraph" style:parent-style-name="Standard">
<style:paragraph-properties fo:text-align="center" fo:margin-bottom="0.5cm" fo:line-height="120%"/>
<style:text-properties fo:font-size="14pt"/>
</style:style>

<style:style style:name="BookMeta" style:family="paragraph" style:parent-style-name="Standard">
<style:paragraph-properties fo:text-align="center" fo:margin-bottom="0.2cm" fo:line-height="120%"/>
<style:text-properties fo:font-size="10pt"/>
</style:style>

<style:style style:name="Cover" style:family="paragraph" style:parent-style-name="Standard">
<style:paragraph-properties fo:text-align="center" fo:line-height="100%"/>
</style:style>

<style:style style:name="SceneBreak" style:family="paragraph" style:parent-style-name="Standard">
<style:paragraph-properties fo:text-align="center" fo:margin-top="0.5cm" fo:margin-bottom="0.5cm"/>
</style:style>

<style:style style:name="Quotation" style:family="paragraph" style:parent-style-name="Standard">
<style:paragraph-properties fo:margin-left="1.25cm" fo:margin-right="1.25cm"/>
<style:text-properties fo:font-style="italic"/>
</style:style>

<style:style style:name="ListItem" style:family="paragraph" style:parent-style-name="Standard">
<style:paragraph-properties fo:text-align="start" fo:margin-left="0.75cm" fo:text-indent="-0.75cm" fo:line-height="120%"/>
</style:style>

<style:style style:name="ListItemNested" style:family="paragraph" style:parent-style-name="ListItem">
<style:paragraph-properties fo:margin-left="1.5cm"/>
</style:style>

<style:style style:name="TocEntry" style:family="paragraph" style:parent-style-name="Standard">
<style:paragraph-properties fo:text-align="start" fo:line-height="120%" fo:margin-bottom="0.1cm"/>
</style:style>

<style:style style:name="CodeBlock" style:family="paragraph" style:parent-style-name="Standard">
<style:paragraph-properties fo:text-align="start" fo:line-height="110%"
 fo:margin-top="0.3cm" fo:margin-bottom="0.3cm" fo:keep-together="always"/>
<style:text-properties style:font-name="Liberation Mono" fo:font-size="10pt"/>
</style:style>

<style:style style:name="TableCell" style:family="paragraph" style:parent-style-name="Standard">
<style:paragraph-properties fo:text-align="start" fo:line-height="120%"/>
<style:text-properties fo:font-size="10pt"/>
</style:style>

<style:style style:name="TableHeader" style:family="paragraph" style:parent-style-name="TableCell">
<style:text-properties fo:font-weight="bold"/>
</style:style>

<style:style style:name="Bold" style:family="text">
<style:text-properties fo:font-weight="bold"/>
</style:style>

<style:style style:name="Italic" style:family="text">
<style:text-properties fo:font-style="italic"/>
</style:style>

<style:style style:name="Underline" style:family="text">
<style:text-properties style:text-underline-style="solid" style:text-underline-width="auto"/>
</style:style>

<style:style style:name="Strike" style:family="text">
<style:text-properties style:text-line-through-style="solid"/>
</style:style>

<style:style style:name="Code" style:family="text">
<style:text-properties style:font-name="Liberation Mono" fo:font-size="10pt"/>
</style:style>

</office:styles>
<office:automatic-styles>
<style:page-layout style:name="PageLayout">
<style:page-layout-properties fo:page-width="21cm" fo:page-height="29.7cm"
 fo:margin-top="2.5cm" fo:margin-bottom="2.5cm" fo:margin-left="2.5cm" fo:margin-right="2.5cm"
 style:print-orientation="portrait"/>
</style:page-layout>
</office:automatic-styles>
<office:master-styles>
<style:master-page style:name="Standard" style:page-layout-name="PageLayout"/>
</office:master-styles>
</office:document-styles>
''';
}
