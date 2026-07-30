import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosa/features/export/data/epub_exporter.dart';
import 'package:prosa/features/export/domain/models/book.dart';
import 'package:prosa/features/export/domain/models/book_metadata.dart';
import 'package:xml/xml.dart';

const _metadata = BookMetadata(
  title: 'O Livro & a Chave',
  author: 'Ana Autora',
  language: 'pt-BR',
  publisher: 'Editora Teste',
  isbn: '978-85-333-0227-3',
  subjects: ['fantasia', 'aventura'],
  rights: '© 2026 Ana Autora',
  description: 'Uma sinopse curta.',
);

Book _book({BookCover? cover, List<BookSection>? appendices}) => Book(
      metadata: _metadata,
      uuid: '11111111-2222-3333-4444-555555555555',
      cover: cover,
      chapters: [
        const BookSection(
          id: 'ch1',
          title: 'A partida',
          blocks: [
            BookBlock(
              type: BookBlockType.paragraph,
              runs: [TextRun('Era uma vez <um> rei & uma rainha.')],
              startsBlock: true,
            ),
            BookBlock(
              type: BookBlockType.paragraph,
              runs: [
                TextRun('Depois veio o '),
                TextRun('fim', bold: true, italic: true),
                TextRun('.'),
              ],
            ),
            BookBlock(type: BookBlockType.divider),
            BookBlock(
              type: BookBlockType.paragraph,
              runs: [TextRun('Outra cena.')],
              startsBlock: true,
            ),
          ],
        ),
      ],
      appendices: appendices ?? const [],
    );

Archive _unzip(Uint8List bytes) => ZipDecoder().decodeBytes(bytes);

String _read(Archive archive, String name) {
  final file = archive.files.firstWhere(
    (f) => f.name == name,
    orElse: () => throw StateError('$name não está no pacote'),
  );
  return utf8.decode(file.readBytes()!);
}

void main() {
  test('o mimetype é a primeira entrada e fica sem compressão', () async {
    // A regra é do formato: é por estes bytes, lidos sem descompactar nada,
    // que o leitor reconhece o arquivo como EPUB.
    final archive = _unzip(await const EpubExporter().build(_book()));

    expect(archive.files.first.name, 'mimetype');
    expect(utf8.decode(archive.files.first.readBytes()!), 'application/epub+zip');
    expect(archive.files.first.compression, CompressionType.none);
  });

  test('todo XML gerado é bem formado', () async {
    final archive = _unzip(await const EpubExporter().build(_book()));

    final xmlFiles = archive.files.where(
      (f) =>
          f.name.endsWith('.xhtml') ||
          f.name.endsWith('.opf') ||
          f.name.endsWith('.ncx') ||
          f.name.endsWith('.xml'),
    );
    expect(xmlFiles, isNotEmpty);

    for (final file in xmlFiles) {
      expect(
        () => XmlDocument.parse(utf8.decode(file.readBytes()!)),
        returnsNormally,
        reason: '${file.name} não é XML válido',
      );
    }
  });

  test('o container aponta para o pacote, e o pacote existe', () async {
    final archive = _unzip(await const EpubExporter().build(_book()));

    final container = XmlDocument.parse(_read(archive, 'META-INF/container.xml'));
    final fullPath = container
        .findAllElements('rootfile')
        .single
        .getAttribute('full-path');

    expect(fullPath, 'OEBPS/content.opf');
    expect(archive.files.map((f) => f.name), contains(fullPath));
  });

  test('todo item do manifesto existe no pacote, e toda entrada da ordem de '
      'leitura existe no manifesto', () async {
    final archive = _unzip(await const EpubExporter().build(_book()));
    final opf = XmlDocument.parse(_read(archive, 'OEBPS/content.opf'));
    final names = archive.files.map((f) => f.name).toSet();

    final ids = <String>{};
    for (final item in opf.findAllElements('item')) {
      ids.add(item.getAttribute('id')!);
      expect(names, contains('OEBPS/${item.getAttribute('href')}'));
    }

    final itemrefs = opf
        .findAllElements('itemref')
        .map((e) => e.getAttribute('idref'))
        .toList();
    expect(itemrefs, isNotEmpty);
    for (final idref in itemrefs) {
      expect(ids, contains(idref));
    }
  });

  test('os metadados vão para o pacote', () async {
    final archive = _unzip(await const EpubExporter().build(_book()));
    final opf = XmlDocument.parse(_read(archive, 'OEBPS/content.opf'));

    String text(String tag) => opf.findAllElements(tag).first.innerText;

    expect(text('dc:title'), 'O Livro & a Chave');
    expect(text('dc:creator'), 'Ana Autora');
    expect(text('dc:language'), 'pt-BR');
    expect(text('dc:publisher'), 'Editora Teste');
    expect(text('dc:rights'), '© 2026 Ana Autora');
    expect(
      opf.findAllElements('dc:subject').map((e) => e.innerText),
      ['fantasia', 'aventura'],
    );
    // Com ISBN, ele é a identidade do livro; sem ele, entra o UUID guardado
    // no projeto.
    expect(text('dc:identifier'), 'urn:isbn:9788533302273');
    expect(
      opf
          .findAllElements('meta')
          .firstWhere((e) => e.getAttribute('property') == 'dcterms:modified')
          .innerText,
      matches(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'),
    );
  });

  test('sem ISBN o livro é identificado pelo UUID do projeto', () async {
    final book = Book(
      metadata: const BookMetadata(title: 'Sem ISBN'),
      uuid: 'abc-123',
      chapters: _book().chapters,
    );
    final archive = _unzip(await const EpubExporter().build(book));
    final opf = XmlDocument.parse(_read(archive, 'OEBPS/content.opf'));

    expect(opf.findAllElements('dc:identifier').first.innerText, 'urn:uuid:abc-123');
  });

  test('o texto sai escapado e com a formatação preservada', () async {
    final archive = _unzip(await const EpubExporter().build(_book()));
    final chapter = _read(archive, 'OEBPS/ch1.xhtml');

    expect(chapter, contains('Era uma vez &lt;um&gt; rei &amp; uma rainha.'));
    expect(chapter, contains('<em><strong>fim</strong></em>'));
    // Primeiro parágrafo do trecho sai sem recuo.
    expect(chapter, contains('<p class="first">'));
    // Quebra de cena.
    expect(chapter, contains('<p class="scene">'));
  });

  test('o sumário lista capítulos e apêndices, com as subseções aninhadas',
      () async {
    final book = _book(
      appendices: const [
        BookSection(
          id: 'ap1',
          title: 'Personagens',
          subsections: [
            BookSection(
              id: 'ap1_1',
              title: 'Ana',
              blocks: [
                BookBlock(
                  type: BookBlockType.paragraph,
                  runs: [TextRun('Alta e calada.')],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final archive = _unzip(await const EpubExporter().build(book));
    final nav = _read(archive, 'OEBPS/nav.xhtml');

    expect(nav, contains('href="ch1.xhtml"'));
    expect(nav, contains('href="ap1.xhtml"'));
    // A subseção mora no arquivo do grupo, marcada por âncora.
    expect(nav, contains('href="ap1.xhtml#ap1_1"'));

    final ncx = XmlDocument.parse(_read(archive, 'OEBPS/toc.ncx'));
    expect(
      ncx.findAllElements('navPoint').map((e) => e.getAttribute('playOrder')),
      ['1', '2', '3'],
    );
  });

  test('a capa entra como imagem, página e metadado', () async {
    final cover = BookCover(
      bytes: Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0x00]),
      mediaType: 'image/jpeg',
      extension: 'jpg',
    );
    final archive = _unzip(await const EpubExporter().build(_book(cover: cover)));
    final opf = XmlDocument.parse(_read(archive, 'OEBPS/content.opf'));

    expect(archive.files.map((f) => f.name), contains('OEBPS/images/cover.jpg'));

    final item = opf.findAllElements('item').firstWhere(
          (e) => e.getAttribute('id') == 'cover-image',
        );
    expect(item.getAttribute('properties'), 'cover-image');
    expect(item.getAttribute('media-type'), 'image/jpeg');

    // Forma antiga, que é como o Kindle acha a capa.
    expect(
      opf.findAllElements('meta').any(
            (e) =>
                e.getAttribute('name') == 'cover' &&
                e.getAttribute('content') == 'cover-image',
          ),
      isTrue,
    );

    // A capa é a primeira página do livro.
    expect(
      opf.findAllElements('itemref').first.getAttribute('idref'),
      'cover',
    );
  });

  test('cada seção de primeiro nível vira um arquivo', () async {
    final book = _book(
      appendices: const [
        BookSection(
          id: 'ap1',
          title: 'Notas',
          subsections: [
            BookSection(
              id: 'ap1_1',
              title: 'Uma nota',
              blocks: [
                BookBlock(type: BookBlockType.paragraph, runs: [TextRun('Texto.')]),
              ],
            ),
          ],
        ),
      ],
    );

    final archive = _unzip(await const EpubExporter().build(book));
    final names = archive.files.map((f) => f.name);

    expect(names, contains('OEBPS/ch1.xhtml'));
    expect(names, contains('OEBPS/ap1.xhtml'));
    expect(_read(archive, 'OEBPS/ap1.xhtml'), contains('id="ap1_1"'));
    // Subseção é âncora dentro do arquivo do grupo, não arquivo próprio.
    expect(names, isNot(contains('OEBPS/ap1_1.xhtml')));
  });
}
