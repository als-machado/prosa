import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../domain/models/book.dart';
import '../domain/models/export_format.dart';
import 'book_exporter.dart';
import 'xhtml_renderer.dart' show escape;

/// Escreve o livro em DOCX (WordprocessingML).
///
/// É o formato que editora e revisor pedem, então o miolo sai com cara de
/// original: Times New Roman 12, entrelinha 1,5, parágrafo justificado com
/// recuo de primeira linha e capítulo começando em página nova.
///
/// Um .docx é um ZIP com as partes ligadas por arquivos de relacionamento —
/// nada é encontrado por caminho, tudo por `rId`. É por isso que link e
/// imagem passam pelo [_Relationships]: quem escreve o parágrafo precisa do
/// identificador antes de o arquivo de relacionamentos existir.
class DocxExporter implements BookExporter {
  const DocxExporter();

  @override
  ExportFormat get format => ExportFormat.docx;

  /// A4 em twips (1/1440 de polegada), com margem de 2,5 cm.
  static const _pageWidth = 11906;
  static const _pageHeight = 16838;
  static const _margin = 1417;

  /// Largura útil da página em EMU (914400 por polegada), para caber a capa.
  static const _contentWidthEmu = (_pageWidth - 2 * _margin) * 635;
  static const _contentHeightEmu = (_pageHeight - 2 * _margin) * 635;

  @override
  Future<Uint8List> build(Book book, {DateTime? modified}) async {
    final rels = _Relationships()..add(_styleRel, 'styles.xml');
    final archive = Archive();

    final cover = book.cover;
    String? coverRelId;
    if (cover != null) {
      final target = 'media/cover.${cover.extension}';
      archive.add(ArchiveFile.bytes('word/$target', cover.bytes));
      coverRelId = rels.add(_imageRel, target);
    }

    // O corpo é montado antes dos relacionamentos irem para o pacote: é ele
    // que descobre quantos links existem.
    final body = _body(book, rels, coverRelId);

    archive
      ..add(ArchiveFile.string('[Content_Types].xml', _contentTypes(cover)))
      ..add(ArchiveFile.string('_rels/.rels', _packageRels))
      ..add(ArchiveFile.string('word/document.xml', body))
      ..add(ArchiveFile.string('word/_rels/document.xml.rels', rels.toXml()))
      ..add(ArchiveFile.string('word/styles.xml', _styles))
      ..add(
        ArchiveFile.string(
          'docProps/core.xml',
          _coreProperties(book, modified ?? DateTime.now()),
        ),
      )
      ..add(ArchiveFile.string('docProps/app.xml', _appProperties));

    return ZipEncoder().encodeBytes(archive);
  }

  // --------------------------------------------------------------- documento

  String _body(Book book, _Relationships rels, String? coverRelId) {
    final out = StringBuffer();
    final metadata = book.metadata;

    if (coverRelId != null && book.cover != null) {
      out.write(_coverParagraph(book.cover!, coverRelId));
    }

    out.write(_paragraph('BookTitle', [TextRun(metadata.title)], rels));
    if (metadata.author.isNotEmpty) {
      out.write(_paragraph('BookAuthor', [TextRun(metadata.author)], rels));
    }
    if (metadata.publisher.isNotEmpty) {
      out.write(_paragraph('BookMeta', [TextRun(metadata.publisher)], rels));
    }
    if (metadata.rights.isNotEmpty) {
      out.write(_paragraph('BookMeta', [TextRun(metadata.rights)], rels));
    }

    out.write(_tableOfContents());

    for (final walked in walkSections(book.sections)) {
      final level = (walked.depth + 1).clamp(1, 6);
      out.write(
        _paragraph('Heading$level', [TextRun(walked.section.title)], rels),
      );
      out.write(_blocks(walked.section.blocks, rels));
    }

    out.write(
      '<w:sectPr><w:pgSz w:w="$_pageWidth" w:h="$_pageHeight"/>'
      '<w:pgMar w:top="$_margin" w:right="$_margin" w:bottom="$_margin" '
      'w:left="$_margin" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>',
    );

    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w:document $_documentNamespaces><w:body>$out</w:body></w:document>\n';
  }

  /// Sumário como campo do Word: nasce vazio e se preenche sozinho quando o
  /// usuário manda atualizar. Uma lista fixa de títulos ficaria com os números
  /// de página errados assim que alguém editasse uma linha do texto.
  String _tableOfContents() {
    return '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
        '<w:r><w:t>Sumário</w:t></w:r></w:p>'
        '<w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r>'
        '<w:r><w:instrText xml:space="preserve"> TOC \\o "1-3" \\h \\z \\u </w:instrText></w:r>'
        '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
        '<w:r><w:t xml:space="preserve">Clique aqui e atualize o campo (F9) '
        'para montar o sumário.</w:t></w:r>'
        '<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>';
  }

  String _blocks(List<BookBlock> blocks, _Relationships rels, {int indent = 0}) {
    final out = StringBuffer();
    var numbered = 0;

    for (final block in blocks) {
      if (block.type != BookBlockType.numberedItem) numbered = 0;

      switch (block.type) {
        case BookBlockType.heading:
          final level = block.level.clamp(1, 6);
          out.write(_paragraph('Heading$level', block.runs, rels));
        case BookBlockType.paragraph:
          out.write(
            _paragraph(block.startsBlock ? 'FirstParagraph' : 'Normal',
                block.runs, rels),
          );
        case BookBlockType.quote:
          out.write(_paragraph('Quotation', block.runs, rels));
        case BookBlockType.bulletedItem:
          out.write(_listItem('•\t', block.runs, rels, indent));
        case BookBlockType.numberedItem:
          numbered++;
          out.write(_listItem('$numbered.\t', block.runs, rels, indent));
        case BookBlockType.todoItem:
          out.write(
            _listItem(
                '${block.checked ? '☑' : '☐'}\t', block.runs, rels, indent),
          );
        case BookBlockType.code:
          out.write(_codeParagraph(block.plainText));
        case BookBlockType.divider:
          out.write(_paragraph('SceneBreak', const [TextRun('* * *')], rels));
        case BookBlockType.image:
          // Só a capa é embutida; imagem no meio do texto viraria mais um
          // relacionamento e mais um cálculo de tamanho por figura.
          break;
        case BookBlockType.table:
          out.write(_table(block, rels));
      }

      if (block.children.isNotEmpty) {
        out.write(_blocks(block.children, rels, indent: indent + 1));
      }
    }
    return out.toString();
  }

  /// Marcador escrito na mão, e não numeração do Word.
  ///
  /// A numeração automática precisaria de um `numbering.xml` inteiro com uma
  /// definição por nível; o número escrito no texto sai igual em qualquer
  /// editor e sobrevive a copiar e colar.
  String _listItem(
    String marker,
    List<TextRun> runs,
    _Relationships rels,
    int indent,
  ) {
    final left = 425 + indent * 425;
    return '<w:p><w:pPr><w:pStyle w:val="ListItem"/>'
        '<w:ind w:left="$left" w:hanging="425"/></w:pPr>'
        '${_run(TextRun(marker))}${_runs(runs, rels)}</w:p>';
  }

  String _codeParagraph(String code) {
    final lines = code.split('\n');
    final out = StringBuffer('<w:p><w:pPr><w:pStyle w:val="CodeBlock"/></w:pPr>');
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) out.write('<w:r><w:br/></w:r>');
      out.write(_run(TextRun(lines[i])));
    }
    out.write('</w:p>');
    return out.toString();
  }

  String _table(BookBlock block, _Relationships rels) {
    final out = StringBuffer(
      '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/>'
      '<w:tblBorders>'
      '${['top', 'left', 'bottom', 'right', 'insideH', 'insideV'].map(
        (side) => '<w:$side w:val="single" w:sz="4" w:space="0" w:color="999999"/>',
      ).join()}'
      '</w:tblBorders></w:tblPr>',
    );

    for (var row = 0; row < block.tableRows.length; row++) {
      out.write('<w:tr>');
      for (final cell in block.tableRows[row]) {
        out.write(
          '<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/></w:tcPr>'
          '${_paragraph(row == 0 ? 'TableHeader' : 'TableCell', cell, rels)}'
          '</w:tc>',
        );
      }
      out.write('</w:tr>');
    }

    // O Word exige um parágrafo depois da tabela; sem ele o arquivo abre
    // com aviso de conteúdo ilegível.
    out.write('</w:tbl><w:p/>');
    return out.toString();
  }

  String _coverParagraph(BookCover cover, String relId) {
    // A capa ocupa a largura útil, ou menos, se assim ela couber em altura.
    var width = _contentWidthEmu;
    var height = (width * cover.aspectRatio).round();
    if (height > _contentHeightEmu) {
      height = _contentHeightEmu;
      width = (height / cover.aspectRatio).round();
    }

    return '<w:p><w:pPr><w:pStyle w:val="Cover"/></w:pPr><w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$width" cy="$height"/>'
        '<wp:docPr id="1" name="Capa"/>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic>'
        '<pic:nvPicPr><pic:cNvPr id="1" name="Capa"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$relId"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$width" cy="$height"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic></wp:inline>'
        '</w:drawing></w:r></w:p>';
  }

  String _paragraph(String style, List<TextRun> runs, _Relationships rels) =>
      '<w:p><w:pPr><w:pStyle w:val="$style"/></w:pPr>${_runs(runs, rels)}</w:p>';

  String _runs(List<TextRun> runs, _Relationships rels) {
    final out = StringBuffer();
    for (final run in runs) {
      final href = run.href;
      if (href == null) {
        out.write(_run(run));
        continue;
      }
      final id = rels.add(_hyperlinkRel, href, external: true);
      out.write('<w:hyperlink r:id="$id">${_run(run, hyperlink: true)}</w:hyperlink>');
    }
    return out.toString();
  }

  String _run(TextRun run, {bool hyperlink = false}) {
    final properties = StringBuffer();
    if (hyperlink) properties.write('<w:rStyle w:val="Hyperlink"/>');
    if (run.code) {
      properties.write(
        '<w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/>',
      );
    }
    if (run.bold) properties.write('<w:b/>');
    if (run.italic) properties.write('<w:i/>');
    if (run.strikethrough) properties.write('<w:strike/>');
    if (run.underline) properties.write('<w:u w:val="single"/>');

    final rPr = properties.isEmpty ? '' : '<w:rPr>$properties</w:rPr>';
    return '<w:r>$rPr<w:t xml:space="preserve">${escape(run.text)}</w:t></w:r>';
  }

  // ------------------------------------------------------------------ partes

  String _contentTypes(BookCover? cover) {
    final imageDefault = cover == null
        ? ''
        : '<Default Extension="${cover.extension}" ContentType="${cover.mediaType}"/>';
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
$imageDefault
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>
''';
  }

  String _coreProperties(Book book, DateTime modified) {
    final metadata = book.metadata;
    final stamp = _timestamp(modified);
    final out = StringBuffer()
      ..writeln('<dc:title>${escape(metadata.title)}</dc:title>');
    if (metadata.author.isNotEmpty) {
      out
        ..writeln('<dc:creator>${escape(metadata.author)}</dc:creator>')
        ..writeln('<cp:lastModifiedBy>${escape(metadata.author)}</cp:lastModifiedBy>');
    }
    if (metadata.description.isNotEmpty) {
      out.writeln('<dc:description>${escape(metadata.description)}</dc:description>');
    }
    if (metadata.subjects.isNotEmpty) {
      out.writeln('<cp:keywords>${escape(metadata.subjects.join(', '))}</cp:keywords>');
    }
    if (metadata.language.isNotEmpty) {
      out.writeln('<dc:language>${escape(metadata.language)}</dc:language>');
    }

    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
$out<dcterms:created xsi:type="dcterms:W3CDTF">$stamp</dcterms:created>
<dcterms:modified xsi:type="dcterms:W3CDTF">$stamp</dcterms:modified>
</cp:coreProperties>
''';
  }

  static String _timestamp(DateTime dateTime) {
    final utc = dateTime.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)}'
        'T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
  }

  static const _styleRel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles';
  static const _imageRel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image';
  static const _hyperlinkRel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink';

  static const _documentNamespaces =
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"';

  static const _packageRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rIdDoc" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
<Relationship Id="rIdCore" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
<Relationship Id="rIdApp" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>
''';

  static const _appProperties = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">
<Application>Prosa</Application>
</Properties>
''';

  static const _styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:docDefaults>
<w:rPrDefault><w:rPr>
<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>
<w:sz w:val="24"/><w:szCs w:val="24"/>
</w:rPr></w:rPrDefault>
<w:pPrDefault><w:pPr>
<w:spacing w:after="0" w:line="360" w:lineRule="auto"/>
<w:jc w:val="both"/>
</w:pPr></w:pPrDefault>
</w:docDefaults>

<w:style w:type="paragraph" w:default="1" w:styleId="Normal">
<w:name w:val="Normal"/>
<w:pPr><w:ind w:firstLine="709"/></w:pPr>
</w:style>

<w:style w:type="paragraph" w:styleId="FirstParagraph">
<w:name w:val="First Paragraph"/><w:basedOn w:val="Normal"/>
<w:pPr><w:ind w:firstLine="0"/></w:pPr>
</w:style>

<w:style w:type="paragraph" w:styleId="Heading1">
<w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>
<w:pPr><w:pageBreakBefore/><w:outlineLvl w:val="0"/><w:ind w:firstLine="0"/>
<w:jc w:val="center"/><w:spacing w:before="480" w:after="360" w:line="240" w:lineRule="auto"/>
<w:keepNext/></w:pPr>
<w:rPr><w:sz w:val="36"/></w:rPr>
</w:style>

<w:style w:type="paragraph" w:styleId="Heading2">
<w:name w:val="heading 2"/><w:basedOn w:val="Normal"/>
<w:pPr><w:outlineLvl w:val="1"/><w:ind w:firstLine="0"/><w:jc w:val="center"/>
<w:spacing w:before="360" w:after="240" w:line="240" w:lineRule="auto"/><w:keepNext/></w:pPr>
<w:rPr><w:sz w:val="30"/></w:rPr>
</w:style>

<w:style w:type="paragraph" w:styleId="Heading3">
<w:name w:val="heading 3"/><w:basedOn w:val="Normal"/>
<w:pPr><w:outlineLvl w:val="2"/><w:ind w:firstLine="0"/><w:jc w:val="left"/>
<w:spacing w:before="280" w:after="160" w:line="240" w:lineRule="auto"/><w:keepNext/></w:pPr>
<w:rPr><w:b/><w:sz w:val="26"/></w:rPr>
</w:style>

<w:style w:type="paragraph" w:styleId="Heading4">
<w:name w:val="heading 4"/><w:basedOn w:val="Heading3"/>
<w:pPr><w:outlineLvl w:val="3"/></w:pPr><w:rPr><w:sz w:val="24"/></w:rPr>
</w:style>

<w:style w:type="paragraph" w:styleId="Heading5">
<w:name w:val="heading 5"/><w:basedOn w:val="Heading4"/>
<w:pPr><w:outlineLvl w:val="4"/></w:pPr><w:rPr><w:i/></w:rPr>
</w:style>

<w:style w:type="paragraph" w:styleId="Heading6">
<w:name w:val="heading 6"/><w:basedOn w:val="Heading5"/>
<w:pPr><w:outlineLvl w:val="5"/></w:pPr>
</w:style>

<w:style w:type="paragraph" w:styleId="BookTitle">
<w:name w:val="Book Title"/><w:basedOn w:val="Normal"/>
<w:pPr><w:ind w:firstLine="0"/><w:jc w:val="center"/>
<w:spacing w:before="2400" w:after="360" w:line="240" w:lineRule="auto"/></w:pPr>
<w:rPr><w:sz w:val="56"/></w:rPr>
</w:style>

<w:style w:type="paragraph" w:styleId="BookAuthor">
<w:name w:val="Book Author"/><w:basedOn w:val="BookTitle"/>
<w:pPr><w:spacing w:before="0" w:after="240"/></w:pPr>
<w:rPr><w:sz w:val="28"/></w:rPr>
</w:style>

<w:style w:type="paragraph" w:styleId="BookMeta">
<w:name w:val="Book Meta"/><w:basedOn w:val="BookAuthor"/>
<w:pPr><w:spacing w:after="120"/></w:pPr><w:rPr><w:sz w:val="20"/></w:rPr>
</w:style>

<w:style w:type="paragraph" w:styleId="Cover">
<w:name w:val="Cover"/><w:basedOn w:val="Normal"/>
<w:pPr><w:ind w:firstLine="0"/><w:jc w:val="center"/>
<w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>
</w:style>

<w:style w:type="paragraph" w:styleId="SceneBreak">
<w:name w:val="Scene Break"/><w:basedOn w:val="Normal"/>
<w:pPr><w:ind w:firstLine="0"/><w:jc w:val="center"/>
<w:spacing w:before="240" w:after="240"/></w:pPr>
</w:style>

<w:style w:type="paragraph" w:styleId="Quotation">
<w:name w:val="Quotation"/><w:basedOn w:val="Normal"/>
<w:pPr><w:ind w:left="709" w:right="709" w:firstLine="0"/></w:pPr>
<w:rPr><w:i/></w:rPr>
</w:style>

<w:style w:type="paragraph" w:styleId="ListItem">
<w:name w:val="List Item"/><w:basedOn w:val="Normal"/>
<w:pPr><w:jc w:val="left"/><w:spacing w:line="240" w:lineRule="auto" w:after="60"/></w:pPr>
</w:style>

<w:style w:type="paragraph" w:styleId="CodeBlock">
<w:name w:val="Code Block"/><w:basedOn w:val="Normal"/>
<w:pPr><w:ind w:firstLine="0"/><w:jc w:val="left"/>
<w:spacing w:line="240" w:lineRule="auto" w:before="120" w:after="120"/><w:keepLines/></w:pPr>
<w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/><w:sz w:val="20"/></w:rPr>
</w:style>

<w:style w:type="paragraph" w:styleId="TableCell">
<w:name w:val="Table Cell"/><w:basedOn w:val="Normal"/>
<w:pPr><w:ind w:firstLine="0"/><w:jc w:val="left"/>
<w:spacing w:line="240" w:lineRule="auto"/></w:pPr>
<w:rPr><w:sz w:val="20"/></w:rPr>
</w:style>

<w:style w:type="paragraph" w:styleId="TableHeader">
<w:name w:val="Table Header"/><w:basedOn w:val="TableCell"/>
<w:rPr><w:b/></w:rPr>
</w:style>

<w:style w:type="character" w:styleId="Hyperlink">
<w:name w:val="Hyperlink"/>
<w:rPr><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr>
</w:style>
</w:styles>
''';
}

/// Os relacionamentos de `word/document.xml`.
///
/// Link e imagem no WordprocessingML não guardam o endereço no parágrafo: o
/// parágrafo guarda um `rId` que é resolvido neste arquivo.
class _Relationships {
  final _entries = <({String id, String type, String target, bool external})>[];

  String add(String type, String target, {bool external = false}) {
    // Dois links para o mesmo endereço podem dividir o mesmo rId.
    for (final entry in _entries) {
      if (entry.type == type && entry.target == target) return entry.id;
    }
    final id = 'rId${_entries.length + 1}';
    _entries.add((id: id, type: type, target: target, external: external));
    return id;
  }

  String toXml() {
    final items = _entries
        .map(
          (e) => '<Relationship Id="${e.id}" Type="${e.type}" '
              'Target="${escape(e.target)}"'
              '${e.external ? ' TargetMode="External"' : ''}/>',
        )
        .join('\n');
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
$items
</Relationships>
''';
  }
}
