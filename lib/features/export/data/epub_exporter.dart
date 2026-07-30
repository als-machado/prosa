import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../domain/models/book.dart';
import '../domain/models/export_format.dart';
import 'book_exporter.dart';
import 'image_loader.dart';
import 'xhtml_renderer.dart';

/// Escreve o livro como EPUB 3.
///
/// Um EPUB é um ZIP com uma estrutura fixa:
///
/// ```text
/// mimetype                 primeiro do arquivo e sem compressão (a regra
///                          existe para que o tipo seja lido pelos bytes)
/// META-INF/container.xml   aponta para o pacote
/// OEBPS/content.opf        metadados + lista de arquivos + ordem de leitura
/// OEBPS/nav.xhtml          sumário do EPUB 3
/// OEBPS/toc.ncx            sumário do EPUB 2, para leitor antigo e Kindle
/// OEBPS/<seção>.xhtml      um arquivo por capítulo/apêndice
/// ```
class EpubExporter implements BookExporter {
  const EpubExporter();

  @override
  ExportFormat get format => ExportFormat.epub;

  static const _oebps = 'OEBPS';

  @override
  Future<Uint8List> build(Book book, {DateTime? modified}) async {
    final archive = Archive();
    final manifest = <_ManifestItem>[];
    final spine = <String>[];

    // O mimetype tem de ser a primeira entrada do ZIP e ficar armazenado sem
    // compressão: é assim que o leitor identifica o arquivo sem descompactar.
    final mimetype = utf8.encode('application/epub+zip');
    archive.add(ArchiveFile.noCompress('mimetype', mimetype.length, mimetype));
    archive.add(ArchiveFile.string('META-INF/container.xml', _containerXml));

    archive.add(ArchiveFile.string('$_oebps/style.css', _styleCss));
    manifest.add(const _ManifestItem('css', 'style.css', 'text/css'));

    final images = await _packImages(book, archive, manifest);
    final renderer = XhtmlRenderer(imageHrefs: images);
    final language = book.metadata.language.isEmpty
        ? 'pt-BR'
        : book.metadata.language;

    final cover = book.cover;
    if (cover != null) {
      final href = 'images/cover.${cover.extension}';
      archive.add(ArchiveFile.bytes('$_oebps/$href', cover.bytes));
      manifest.add(
        _ManifestItem('cover-image', href, cover.mediaType,
            properties: 'cover-image'),
      );

      archive.add(
        ArchiveFile.string(
          '$_oebps/cover.xhtml',
          _xhtmlDocument(
            title: 'Capa',
            language: language,
            body: '<section epub:type="cover">\n'
                '<div class="cover"><img src="${escape(href)}" alt="Capa"/></div>\n'
                '</section>',
          ),
        ),
      );
      manifest.add(
        const _ManifestItem('cover', 'cover.xhtml', 'application/xhtml+xml'),
      );
      spine.add('cover');
    }

    archive.add(
      ArchiveFile.string(
        '$_oebps/titlepage.xhtml',
        _xhtmlDocument(
          title: book.metadata.title,
          language: language,
          body: _titlePageBody(book),
        ),
      ),
    );
    manifest.add(
      const _ManifestItem('titlepage', 'titlepage.xhtml', 'application/xhtml+xml'),
    );
    spine.add('titlepage');

    archive.add(
      ArchiveFile.string(
        '$_oebps/nav.xhtml',
        _xhtmlDocument(
          title: 'Sumário',
          language: language,
          body: _navBody(book),
        ),
      ),
    );
    manifest.add(
      const _ManifestItem('nav', 'nav.xhtml', 'application/xhtml+xml',
          properties: 'nav'),
    );
    spine.add('nav');

    for (final (section, epubType) in [
      ...book.chapters.map((s) => (s, 'chapter')),
      ...book.appendices.map((s) => (s, 'appendix')),
    ]) {
      final href = '${section.id}.xhtml';
      archive.add(
        ArchiveFile.string(
          '$_oebps/$href',
          _xhtmlDocument(
            title: section.title,
            language: language,
            body: _sectionBody(renderer, section, 0, epubType),
          ),
        ),
      );
      manifest.add(
        _ManifestItem(
          section.id,
          href,
          'application/xhtml+xml',
          // Imagem de fora do pacote precisa ser declarada, senão o arquivo
          // não valida (e o leitor não sabe que vai precisar de rede).
          properties: _hasRemoteImage(section) ? 'remote-resources' : null,
        ),
      );
      spine.add(section.id);
    }

    archive.add(ArchiveFile.string('$_oebps/toc.ncx', _tocNcx(book)));
    manifest.add(
      const _ManifestItem('ncx', 'toc.ncx', 'application/x-dtbncx+xml'),
    );

    archive.add(
      ArchiveFile.string(
        '$_oebps/content.opf',
        _packageDocument(book, manifest, spine, modified ?? DateTime.now()),
      ),
    );

    return ZipEncoder().encodeBytes(archive);
  }

  // ------------------------------------------------------------------ imagens

  Future<Map<String, String>> _packImages(
    Book book,
    Archive archive,
    List<_ManifestItem> manifest,
  ) async {
    final paths = <String>{};
    void scan(BookSection section) {
      for (final block in _flatten(section.blocks)) {
        final url = block.imageUrl;
        if (block.type != BookBlockType.image || url == null) continue;
        if (url.startsWith('http://') || url.startsWith('https://')) continue;
        paths.add(url);
      }
      section.subsections.forEach(scan);
    }

    book.sections.forEach(scan);

    final hrefs = <String, String>{};
    final sorted = paths.toList()..sort();
    for (final path in sorted) {
      try {
        final image = await loadExportImage(path);
        final id = 'img${hrefs.length + 1}';
        final href = 'images/$id.${image.extension}';
        archive.add(ArchiveFile.bytes('$_oebps/$href', image.bytes));
        manifest.add(_ManifestItem(id, href, image.mediaType));
        hrefs[path] = href;
      } catch (_) {
        // Imagem ilegível ou apagada depois de citada no texto: o livro sai
        // sem ela em vez de a exportação inteira falhar.
      }
    }
    return hrefs;
  }

  Iterable<BookBlock> _flatten(List<BookBlock> blocks) sync* {
    for (final block in blocks) {
      yield block;
      yield* _flatten(block.children);
    }
  }

  bool _hasRemoteImage(BookSection section) {
    final inBlocks = _flatten(section.blocks).any(
      (b) =>
          b.type == BookBlockType.image &&
          (b.imageUrl?.startsWith('http') ?? false),
    );
    return inBlocks || section.subsections.any(_hasRemoteImage);
  }

  // -------------------------------------------------------------- documentos

  String _sectionBody(
    XhtmlRenderer renderer,
    BookSection section,
    int depth,
    String? epubType,
  ) {
    final level = (depth + 1).clamp(1, 6);
    final type = epubType == null ? '' : ' epub:type="$epubType"';
    final out = StringBuffer('<section id="${section.id}"$type>\n')
      ..writeln('<h$level>${escape(section.title)}</h$level>')
      ..write(renderer.renderBlocks(section.blocks));

    for (final subsection in section.subsections) {
      out.write(_sectionBody(renderer, subsection, depth + 1, null));
    }

    out.writeln('</section>');
    return out.toString();
  }

  String _titlePageBody(Book book) {
    final metadata = book.metadata;
    final out = StringBuffer('<section epub:type="titlepage" class="titlepage">\n')
      ..writeln('<h1 class="book-title">${escape(metadata.title)}</h1>');
    if (metadata.author.isNotEmpty) {
      out.writeln('<p class="book-author">${escape(metadata.author)}</p>');
    }
    if (metadata.publisher.isNotEmpty) {
      out.writeln('<p class="book-publisher">${escape(metadata.publisher)}</p>');
    }
    if (metadata.rights.isNotEmpty) {
      out.writeln('<p class="book-rights">${escape(metadata.rights)}</p>');
    }
    out.writeln('</section>');
    return out.toString();
  }

  String _navBody(Book book) {
    String entries(List<BookSection> sections, String file) {
      final out = StringBuffer('<ol>\n');
      for (final section in sections) {
        final href = file.isEmpty ? '${section.id}.xhtml' : '$file#${section.id}';
        out.write('<li><a href="$href">${escape(section.title)}</a>');
        if (section.subsections.isNotEmpty) {
          out.write(
            '\n${entries(section.subsections, file.isEmpty ? '${section.id}.xhtml' : file)}',
          );
        }
        out.writeln('</li>');
      }
      out.write('</ol>');
      return out.toString();
    }

    final out = StringBuffer()
      ..writeln('<nav epub:type="toc" id="toc">')
      ..writeln('<h1>Sumário</h1>')
      ..writeln(entries(book.sections, ''))
      ..writeln('</nav>')
      ..writeln('<nav epub:type="landmarks" hidden="hidden">')
      ..writeln('<h1>Marcadores</h1>')
      ..writeln('<ol>');
    if (book.cover != null) {
      out.writeln('<li><a epub:type="cover" href="cover.xhtml">Capa</a></li>');
    }
    out.writeln('<li><a epub:type="toc" href="nav.xhtml">Sumário</a></li>');
    if (book.sections.isNotEmpty) {
      out.writeln(
        '<li><a epub:type="bodymatter" href="${book.sections.first.id}.xhtml">'
        'Início</a></li>',
      );
    }
    out
      ..writeln('</ol>')
      ..writeln('</nav>');
    return out.toString();
  }

  String _tocNcx(Book book) {
    var playOrder = 0;

    String points(List<BookSection> sections, String file) {
      final out = StringBuffer();
      for (final section in sections) {
        final href = file.isEmpty ? '${section.id}.xhtml' : '$file#${section.id}';
        playOrder++;
        out
          ..writeln('<navPoint id="nav-${section.id}" playOrder="$playOrder">')
          ..writeln('<navLabel><text>${escape(section.title)}</text></navLabel>')
          ..writeln('<content src="$href"/>');
        if (section.subsections.isNotEmpty) {
          out.write(
            points(section.subsections,
                file.isEmpty ? '${section.id}.xhtml' : file),
          );
        }
        out.writeln('</navPoint>');
      }
      return out.toString();
    }

    final navMap = points(book.sections, '');
    return '''<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
<head>
<meta name="dtb:uid" content="${escape(_identifier(book))}"/>
<meta name="dtb:depth" content="${_depth(book.sections).clamp(1, 9)}"/>
<meta name="dtb:totalPageCount" content="0"/>
<meta name="dtb:maxPageNumber" content="0"/>
</head>
<docTitle><text>${escape(book.metadata.title)}</text></docTitle>
<navMap>
$navMap</navMap>
</ncx>
''';
  }

  int _depth(List<BookSection> sections) {
    var deepest = 0;
    for (final section in sections) {
      final depth = 1 + _depth(section.subsections);
      if (depth > deepest) deepest = depth;
    }
    return deepest;
  }

  String _packageDocument(
    Book book,
    List<_ManifestItem> manifest,
    List<String> spine,
    DateTime modified,
  ) {
    final metadata = book.metadata;
    final language = metadata.language.isEmpty ? 'pt-BR' : metadata.language;
    final title = metadata.title.isEmpty ? 'Sem título' : metadata.title;

    final meta = StringBuffer()
      ..writeln(
        '<dc:identifier id="book-id">${escape(_identifier(book))}</dc:identifier>',
      )
      ..writeln('<dc:title>${escape(title)}</dc:title>')
      ..writeln('<dc:language>${escape(language)}</dc:language>')
      ..writeln(
        '<meta property="dcterms:modified">${_timestamp(modified)}</meta>',
      );

    if (metadata.author.isNotEmpty) {
      meta
        ..writeln('<dc:creator id="creator">${escape(metadata.author)}</dc:creator>')
        ..writeln(
          '<meta refines="#creator" property="role" scheme="marc:relators">aut</meta>',
        );
    }
    if (metadata.publisher.isNotEmpty) {
      meta.writeln('<dc:publisher>${escape(metadata.publisher)}</dc:publisher>');
    }
    if (metadata.description.isNotEmpty) {
      meta.writeln(
        '<dc:description>${escape(metadata.description)}</dc:description>',
      );
    }
    if (metadata.rights.isNotEmpty) {
      meta.writeln('<dc:rights>${escape(metadata.rights)}</dc:rights>');
    }
    for (final subject in metadata.subjects.where((s) => s.trim().isNotEmpty)) {
      meta.writeln('<dc:subject>${escape(subject.trim())}</dc:subject>');
    }
    final publishedAt = metadata.publishedAt;
    if (publishedAt != null) {
      meta.writeln('<dc:date>${_date(publishedAt)}</dc:date>');
    }
    if (book.cover != null) {
      // Forma antiga, que o Kindle ainda usa para achar a capa. Continua
      // aceita no EPUB 3 e convive com o properties="cover-image".
      meta.writeln('<meta name="cover" content="cover-image"/>');
    }

    final items = manifest
        .map((item) => '<item id="${item.id}" href="${item.href}" '
            'media-type="${item.mediaType}"'
            '${item.properties == null ? '' : ' properties="${item.properties}"'}/>')
        .join('\n');

    final itemrefs =
        spine.map((id) => '<itemref idref="$id"/>').join('\n');

    return '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id" xml:lang="${escape(language)}">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
$meta</metadata>
<manifest>
$items
</manifest>
<spine toc="ncx">
$itemrefs
</spine>
</package>
''';
  }

  String _identifier(Book book) {
    final isbn = book.metadata.isbn.replaceAll(RegExp(r'[\s-]'), '');
    return isbn.isEmpty ? 'urn:uuid:${book.uuid}' : 'urn:isbn:$isbn';
  }

  String _xhtmlDocument({
    required String title,
    required String language,
    required String body,
  }) =>
      '''<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="${escape(language)}" lang="${escape(language)}">
<head>
<meta charset="utf-8"/>
<title>${escape(title)}</title>
<link rel="stylesheet" type="text/css" href="style.css"/>
</head>
<body>
$body</body>
</html>
''';

  static String _timestamp(DateTime dateTime) {
    final utc = dateTime.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)}'
        'T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
  }

  static String _date(DateTime dateTime) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dateTime.year}-${two(dateTime.month)}-${two(dateTime.day)}';
  }

  static const _containerXml = '''<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles>
<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
</rootfiles>
</container>
''';

  static const _styleCss = '''@charset "utf-8";

body {
  margin: 0 5%;
  font-family: Georgia, "Times New Roman", serif;
  line-height: 1.5;
  text-align: justify;
  -epub-hyphens: auto;
  hyphens: auto;
  widows: 2;
  orphans: 2;
}

h1, h2, h3, h4, h5, h6 {
  font-weight: normal;
  text-align: center;
  line-height: 1.2;
  page-break-after: avoid;
  break-after: avoid;
}

h1 { font-size: 1.6em; margin: 2em 0 1.5em; }
h2 { font-size: 1.3em; margin: 1.8em 0 1em; }
h3 { font-size: 1.1em; margin: 1.5em 0 0.8em; }
h4, h5, h6 { font-size: 1em; margin: 1.2em 0 0.6em; }

p { margin: 0; text-indent: 1.2em; }

/* Primeiro parágrafo de um trecho não leva recuo — é regra de composição de
   livro: o recuo existe para separar parágrafos, e não há o que separar. */
p.first { text-indent: 0; }

p.scene {
  text-indent: 0;
  text-align: center;
  margin: 1.5em 0;
  letter-spacing: 0.4em;
}

blockquote {
  margin: 1em 2em;
  font-style: italic;
}

blockquote p { text-indent: 0; }

ul, ol { margin: 1em 0 1em 1.5em; text-align: left; }
ul.todo { list-style: none; margin-left: 0.5em; }
li { margin: 0.3em 0; }

pre {
  margin: 1em 0;
  padding: 0.8em;
  background: rgba(128, 128, 128, 0.12);
  white-space: pre-wrap;
  word-wrap: break-word;
  text-align: left;
}

pre, code { font-family: "DejaVu Sans Mono", monospace; font-size: 0.9em; }

table {
  margin: 1em auto;
  border-collapse: collapse;
  text-align: left;
}

th, td {
  border: 1px solid rgba(128, 128, 128, 0.5);
  padding: 0.3em 0.6em;
}

div.image { margin: 1em 0; text-align: center; }
div.image img { max-width: 100%; }

div.cover { margin: 0; padding: 0; text-align: center; }
div.cover img { max-width: 100%; height: auto; }

section.titlepage { text-align: center; margin-top: 20%; }
h1.book-title { font-size: 2em; margin-bottom: 0.5em; }
p.book-author { text-indent: 0; font-size: 1.2em; margin-bottom: 2em; }
p.book-publisher, p.book-rights {
  text-indent: 0;
  font-size: 0.9em;
  margin-top: 0.5em;
}

nav#toc ol { list-style: none; margin-left: 1em; }
nav#toc a { text-decoration: none; }
''';
}

class _ManifestItem {
  final String id;
  final String href;
  final String mediaType;
  final String? properties;

  const _ManifestItem(this.id, this.href, this.mediaType, {this.properties});
}
