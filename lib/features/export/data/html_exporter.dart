import 'dart:convert';
import 'dart:typed_data';

import '../domain/models/book.dart';
import '../domain/models/export_format.dart';
import 'book_exporter.dart';
import 'image_loader.dart';
import 'xhtml_renderer.dart';

/// Escreve o livro como uma página HTML só.
///
/// Tudo vai dentro do arquivo — estilo e imagens viram `data:` — para que o
/// livro continue inteiro depois de ser anexado num e-mail ou copiado para um
/// pendrive. É a diferença entre um arquivo e uma pasta que não pode ser
/// desmontada.
class HtmlExporter implements BookExporter {
  const HtmlExporter();

  @override
  ExportFormat get format => ExportFormat.html;

  @override
  Future<Uint8List> build(Book book, {DateTime? modified}) async {
    final metadata = book.metadata;
    final language = metadata.language.isEmpty ? 'pt-BR' : metadata.language;
    final renderer = XhtmlRenderer(imageHrefs: await _dataUris(book));

    final out = StringBuffer()
      ..writeln('<!DOCTYPE html>')
      ..writeln('<html lang="${escape(language)}">')
      ..writeln('<head>')
      ..writeln('<meta charset="utf-8"/>')
      ..writeln(
        '<meta name="viewport" content="width=device-width, initial-scale=1"/>',
      )
      ..writeln(
        '<title>${escape(metadata.title.isEmpty ? 'Livro' : metadata.title)}</title>',
      );

    if (metadata.author.isNotEmpty) {
      out.writeln('<meta name="author" content="${escape(metadata.author)}"/>');
    }
    if (metadata.description.isNotEmpty) {
      out.writeln(
        '<meta name="description" content="${escape(metadata.description)}"/>',
      );
    }
    if (metadata.subjects.isNotEmpty) {
      out.writeln(
        '<meta name="keywords" content="${escape(metadata.subjects.join(', '))}"/>',
      );
    }

    out
      ..writeln('<style>')
      ..writeln(_css)
      ..writeln('</style>')
      ..writeln('</head>')
      ..writeln('<body>');

    final cover = book.cover;
    if (cover != null) {
      final uri = 'data:${cover.mediaType};base64,${base64Encode(cover.bytes)}';
      out.writeln('<div class="cover"><img src="$uri" alt="Capa"/></div>');
    }

    out
      ..writeln('<header class="titlepage">')
      ..writeln('<h1>${escape(metadata.title)}</h1>');
    if (metadata.author.isNotEmpty) {
      out.writeln('<p class="author">${escape(metadata.author)}</p>');
    }
    if (metadata.publisher.isNotEmpty) {
      out.writeln('<p class="publisher">${escape(metadata.publisher)}</p>');
    }
    if (metadata.rights.isNotEmpty) {
      out.writeln('<p class="rights">${escape(metadata.rights)}</p>');
    }
    out.writeln('</header>');

    out
      ..writeln('<nav class="toc">')
      ..writeln('<h2>Sumário</h2>')
      ..writeln(_toc(book.sections))
      ..writeln('</nav>');

    for (final walked in walkSections(book.sections)) {
      final level = (walked.depth + 2).clamp(2, 6);
      out
        ..writeln('<section id="${walked.section.id}" class="depth-${walked.depth}">')
        ..writeln('<h$level>${escape(walked.section.title)}</h$level>')
        ..write(renderer.renderBlocks(walked.section.blocks))
        ..writeln('</section>');
    }

    out
      ..writeln('</body>')
      ..writeln('</html>');

    return Uint8List.fromList(utf8.encode(out.toString()));
  }

  String _toc(List<BookSection> sections) {
    final out = StringBuffer('<ol>');
    for (final section in sections) {
      out.write('<li><a href="#${section.id}">${escape(section.title)}</a>');
      if (section.subsections.isNotEmpty) out.write(_toc(section.subsections));
      out.writeln('</li>');
    }
    out.write('</ol>');
    return out.toString();
  }

  /// Imagens do texto viram `data:` também; imagem remota fica com o endereço
  /// original, que é o único jeito de ela continuar aparecendo.
  Future<Map<String, String>> _dataUris(Book book) async {
    final paths = <String>{};
    for (final walked in walkSections(book.sections)) {
      for (final block in _flatten(walked.section.blocks)) {
        final url = block.imageUrl;
        if (block.type != BookBlockType.image || url == null) continue;
        if (url.startsWith('http://') || url.startsWith('https://')) continue;
        paths.add(url);
      }
    }

    final uris = <String, String>{};
    for (final path in paths) {
      try {
        final image = await loadExportImage(path);
        uris[path] =
            'data:${image.mediaType};base64,${base64Encode(image.bytes)}';
      } catch (_) {
        // Imagem ilegível ou apagada: sai do livro sem derrubar a exportação.
      }
    }
    return uris;
  }

  Iterable<BookBlock> _flatten(List<BookBlock> blocks) sync* {
    for (final block in blocks) {
      yield block;
      yield* _flatten(block.children);
    }
  }

  static const _css = '''
:root { color-scheme: light dark; }

body {
  max-width: 34em;
  margin: 0 auto;
  padding: 2em 1.2em 6em;
  font-family: Georgia, "Times New Roman", serif;
  font-size: 1.05em;
  line-height: 1.6;
  text-align: justify;
  hyphens: auto;
}

h1, h2, h3, h4, h5, h6 {
  font-weight: normal;
  text-align: center;
  line-height: 1.25;
}

section { margin-top: 4em; }
section.depth-0 > h2 { font-size: 1.7em; margin-bottom: 1.5em; }
section.depth-1 { margin-top: 2.5em; }

p { margin: 0; text-indent: 1.2em; }
p.first { text-indent: 0; }

p.scene {
  text-indent: 0;
  text-align: center;
  margin: 1.5em 0;
  letter-spacing: 0.4em;
}

blockquote { margin: 1em 2em; font-style: italic; }
blockquote p { text-indent: 0; }

ul, ol { margin: 1em 0 1em 1.5em; text-align: left; }
ul.todo { list-style: none; margin-left: 0.5em; }

pre {
  padding: 0.8em;
  background: rgba(128, 128, 128, 0.12);
  white-space: pre-wrap;
  text-align: left;
  overflow-x: auto;
}

pre, code { font-family: ui-monospace, "DejaVu Sans Mono", monospace; font-size: 0.9em; }

table { margin: 1em auto; border-collapse: collapse; text-align: left; }
th, td { border: 1px solid rgba(128, 128, 128, 0.5); padding: 0.3em 0.6em; }

div.image { margin: 1.5em 0; text-align: center; }
div.image img, div.cover img { max-width: 100%; height: auto; }

div.cover { text-align: center; margin-bottom: 3em; }

header.titlepage { text-align: center; margin-bottom: 3em; }
header.titlepage h1 { font-size: 2.2em; margin-bottom: 0.3em; }
header.titlepage p { text-indent: 0; margin: 0.2em 0; }
header.titlepage .author { font-size: 1.2em; }
header.titlepage .publisher, header.titlepage .rights { font-size: 0.85em; opacity: 0.75; }

nav.toc { margin-bottom: 3em; }
nav.toc h2 { font-size: 1.2em; }
nav.toc ol { list-style: none; text-align: left; padding-left: 1em; }
nav.toc a { text-decoration: none; }
nav.toc a:hover { text-decoration: underline; }

@media print {
  body { max-width: none; }
  nav.toc { display: none; }
  section.depth-0 { page-break-before: always; }
}
''';
}
