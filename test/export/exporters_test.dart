import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prosa/features/export/data/docx_exporter.dart';
import 'package:prosa/features/export/data/html_exporter.dart';
import 'package:prosa/features/export/data/odt_exporter.dart';
import 'package:prosa/features/export/data/pdf_exporter.dart';
import 'package:prosa/features/export/data/txt_exporter.dart';
import 'package:prosa/features/export/domain/models/book.dart';
import 'package:prosa/features/export/domain/models/book_metadata.dart';
import 'package:xml/xml.dart';

const _metadata = BookMetadata(
  title: 'O Livro & a Chave',
  author: 'Ana Autora',
  language: 'pt-BR',
  publisher: 'Editora Teste',
  subjects: ['fantasia'],
  rights: '© 2026 Ana Autora',
  description: 'Uma sinopse curta.',
);

/// Um livro com um pouco de tudo o que o miolo pode conter.
Book get _book => const Book(
      metadata: _metadata,
      uuid: 'uuid-1',
      chapters: [
        BookSection(
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
                TextRun('Veio o '),
                TextRun('fim', bold: true, italic: true),
                TextRun(', com '),
                TextRun('link', href: 'https://exemplo.org'),
                TextRun('.'),
              ],
            ),
            BookBlock(type: BookBlockType.divider),
            BookBlock(
              type: BookBlockType.paragraph,
              runs: [TextRun('Outra cena.')],
              startsBlock: true,
            ),
            BookBlock(type: BookBlockType.bulletedItem, runs: [TextRun('um')]),
            BookBlock(type: BookBlockType.bulletedItem, runs: [TextRun('dois')]),
            BookBlock(
              type: BookBlockType.code,
              runs: [TextRun('linha um\nlinha dois')],
            ),
          ],
        ),
      ],
      appendices: [
        BookSection(
          id: 'ap1',
          title: 'Notas',
          subsections: [
            BookSection(
              id: 'ap1_1',
              title: 'Clima',
              blocks: [
                BookBlock(
                  type: BookBlockType.table,
                  tableRows: [
                    [
                      [TextRun('Estação')],
                      [TextRun('Efeito')],
                    ],
                    [
                      [TextRun('Inverno')],
                      [TextRun('Neve')],
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

/// JPEG de verdade: o PDF decodifica a imagem para embutir, então quatro
/// bytes com cara de cabeçalho não bastam.
BookCover get _cover => BookCover(
      bytes: img.encodeJpg(img.Image(width: 40, height: 60)),
      mediaType: 'image/jpeg',
      extension: 'jpg',
      width: 1600,
      height: 2400,
    );

Archive _unzip(Uint8List bytes) => ZipDecoder().decodeBytes(bytes);

String _read(Archive archive, String name) {
  final file = archive.files.firstWhere(
    (f) => f.name == name,
    orElse: () => throw StateError('$name não está no pacote'),
  );
  return utf8.decode(file.readBytes()!);
}

void _expectWellFormedXml(Archive archive) {
  final xmlFiles = archive.files.where((f) => f.name.endsWith('.xml'));
  expect(xmlFiles, isNotEmpty);
  for (final file in xmlFiles) {
    expect(
      () => XmlDocument.parse(utf8.decode(file.readBytes()!)),
      returnsNormally,
      reason: '${file.name} não é XML válido',
    );
  }
}

void main() {
  // O exportador de PDF lê as fontes embutidas pelo rootBundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DOCX', () {
    test('tem as partes que o Word exige e todas são XML válido', () async {
      final archive = _unzip(await const DocxExporter().build(_book));
      final names = archive.files.map((f) => f.name).toSet();

      expect(
        names,
        containsAll([
          '[Content_Types].xml',
          '_rels/.rels',
          'word/document.xml',
          'word/_rels/document.xml.rels',
          'word/styles.xml',
          'docProps/core.xml',
          'docProps/app.xml',
        ]),
      );
      _expectWellFormedXml(archive);
    });

    test('o texto sai escapado, formatado e com o link ligado por rId',
        () async {
      final archive = _unzip(await const DocxExporter().build(_book));
      final document = _read(archive, 'word/document.xml');
      final rels = _read(archive, 'word/_rels/document.xml.rels');

      expect(document, contains('Era uma vez &lt;um&gt; rei &amp; uma rainha.'));
      expect(document, contains('<w:b/>'));
      expect(document, contains('<w:i/>'));

      // O parágrafo não guarda o endereço: guarda um rId que precisa existir
      // no arquivo de relacionamentos.
      final match = RegExp(r'<w:hyperlink r:id="(rId\d+)">').firstMatch(document);
      expect(match, isNotNull);
      expect(rels, contains('Id="${match!.group(1)}"'));
      expect(rels, contains('https://exemplo.org'));
      expect(rels, contains('TargetMode="External"'));
    });

    test('todo estilo usado no documento está declarado', () async {
      final archive = _unzip(await const DocxExporter().build(_book));
      final document = _read(archive, 'word/document.xml');
      final styles = _read(archive, 'word/styles.xml');

      final used = RegExp(r'<w:pStyle w:val="([^"]+)"/>')
          .allMatches(document)
          .map((m) => m.group(1)!)
          .toSet();
      expect(used, isNotEmpty);

      final declared = RegExp(r'w:styleId="([^"]+)"')
          .allMatches(styles)
          .map((m) => m.group(1)!)
          .toSet();
      expect(declared, containsAll(used));
    });

    test('a tabela é seguida de um parágrafo', () async {
      // Sem ele o Word abre o arquivo reclamando de conteúdo ilegível.
      final archive = _unzip(await const DocxExporter().build(_book));
      expect(_read(archive, 'word/document.xml'), contains('</w:tbl><w:p/>'));
    });

    test('a capa entra como imagem embutida', () async {
      final archive = _unzip(
        await const DocxExporter().build(
          Book(
            metadata: _metadata,
            uuid: 'uuid-1',
            cover: _cover,
            chapters: _book.chapters,
          ),
        ),
      );

      expect(archive.files.map((f) => f.name), contains('word/media/cover.jpg'));
      expect(_read(archive, 'word/document.xml'), contains('<w:drawing>'));
      expect(
        _read(archive, '[Content_Types].xml'),
        contains('Extension="jpg" ContentType="image/jpeg"'),
      );
    });

    test('os metadados vão para docProps', () async {
      final archive = _unzip(await const DocxExporter().build(_book));
      final core = XmlDocument.parse(_read(archive, 'docProps/core.xml'));

      expect(core.findAllElements('dc:title').first.innerText, 'O Livro & a Chave');
      expect(core.findAllElements('dc:creator').first.innerText, 'Ana Autora');
      expect(core.findAllElements('dc:language').first.innerText, 'pt-BR');
    });
  });

  group('ODT', () {
    test('o mimetype é a primeira entrada e fica sem compressão', () async {
      final archive = _unzip(await const OdtExporter().build(_book));

      expect(archive.files.first.name, 'mimetype');
      expect(
        utf8.decode(archive.files.first.readBytes()!),
        'application/vnd.oasis.opendocument.text',
      );
      expect(archive.files.first.compression, CompressionType.none);
    });

    test('tem as partes do OpenDocument e todas são XML válido', () async {
      final archive = _unzip(await const OdtExporter().build(_book));

      expect(
        archive.files.map((f) => f.name),
        containsAll([
          'META-INF/manifest.xml',
          'content.xml',
          'styles.xml',
          'meta.xml',
        ]),
      );
      _expectWellFormedXml(archive);
    });

    test('títulos saem como text:h com o nível certo', () async {
      final content = XmlDocument.parse(
        _read(_unzip(await const OdtExporter().build(_book)), 'content.xml'),
      );
      final headings = content.findAllElements('text:h').toList();

      expect(headings.map((h) => h.innerText), contains('A partida'));
      final chapter =
          headings.firstWhere((h) => h.innerText.contains('A partida'));
      expect(chapter.getAttribute('text:outline-level'), '1');

      final nested = headings.firstWhere((h) => h.innerText.contains('Clima'));
      expect(nested.getAttribute('text:outline-level'), '2');
    });

    test('todo estilo usado está declarado em styles.xml', () async {
      final archive = _unzip(await const OdtExporter().build(_book));
      final content = _read(archive, 'content.xml');
      final styles = _read(archive, 'styles.xml');

      final used = RegExp(r'text:style-name="([^"]+)"')
          .allMatches(content)
          .map((m) => m.group(1)!)
          .toSet();
      final declared = RegExp(r'style:name="([^"]+)"')
          .allMatches(styles)
          .map((m) => m.group(1)!)
          .toSet();

      expect(used, isNotEmpty);
      expect(declared, containsAll(used));
    });

    test('a capa é embutida e declarada no manifesto', () async {
      final archive = _unzip(
        await const OdtExporter().build(
          Book(
            metadata: _metadata,
            uuid: 'uuid-1',
            cover: _cover,
            chapters: _book.chapters,
          ),
        ),
      );

      expect(archive.files.map((f) => f.name), contains('Pictures/cover.jpg'));
      expect(
        _read(archive, 'META-INF/manifest.xml'),
        contains('manifest:full-path="Pictures/cover.jpg"'),
      );
      // Proporção preservada: 1600×2400 numa largura de 16 cm dá 24 cm.
      expect(_read(archive, 'content.xml'), contains('svg:height="24.00cm"'));
    });
  });

  group('HTML', () {
    test('sai uma página só, com estilo dentro', () async {
      final html = utf8.decode(await const HtmlExporter().build(_book));

      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('<style>'));
      expect(html, isNot(contains('<link rel="stylesheet"')));
      expect(html, contains('lang="pt-BR"'));
    });

    test('o sumário aponta para as âncoras das seções', () async {
      final html = utf8.decode(await const HtmlExporter().build(_book));

      expect(html, contains('href="#ch1"'));
      expect(html, contains('href="#ap1_1"'));
      expect(html, contains('id="ch1"'));
      expect(html, contains('id="ap1_1"'));
    });

    test('o texto sai escapado e formatado', () async {
      final html = utf8.decode(await const HtmlExporter().build(_book));

      expect(html, contains('Era uma vez &lt;um&gt; rei &amp; uma rainha.'));
      expect(html, contains('<em><strong>fim</strong></em>'));
      expect(html, contains('<a href="https://exemplo.org">link</a>'));
      expect(html, contains('<p class="scene">'));
    });

    test('a capa vira data: para o arquivo continuar inteiro sozinho',
        () async {
      final html = utf8.decode(
        await const HtmlExporter().build(
          Book(
            metadata: _metadata,
            uuid: 'uuid-1',
            cover: _cover,
            chapters: _book.chapters,
          ),
        ),
      );

      expect(html, contains('src="data:image/jpeg;base64,'));
    });
  });

  group('TXT', () {
    test('abre com título e autor', () async {
      final txt = utf8.decode(await const TxtExporter().build(_book));
      expect(txt, startsWith('O LIVRO & A CHAVE\nAna Autora'));
    });

    test('título de capítulo vem sublinhado do tamanho do título', () async {
      final txt = utf8.decode(await const TxtExporter().build(_book));
      expect(txt, contains('A partida\n=========\n'));
      expect(txt, contains('Clima\n-----\n'));
    });

    test('a formatação vira o texto que estava escrito', () async {
      final txt = utf8.decode(await const TxtExporter().build(_book));

      expect(txt, contains('Veio o fim, com link.'));
      expect(txt, isNot(contains('**')));
      expect(txt, isNot(contains('<strong>')));
      expect(txt, contains('* * *'));
      expect(txt, contains('- um\n- dois'));
    });

    test('a tabela vira linhas separadas por barra', () async {
      final txt = utf8.decode(await const TxtExporter().build(_book));
      expect(txt, contains('Estação | Efeito'));
      expect(txt, contains('Inverno | Neve'));
    });
  });

  group('PDF', () {
    test('gera um PDF bem formado', () async {
      final bytes = await const PdfExporter().build(_book);
      final head = utf8.decode(bytes.sublist(0, 8), allowMalformed: true);
      final tail = utf8.decode(
        bytes.sublist(bytes.length - 32),
        allowMalformed: true,
      );

      expect(head, startsWith('%PDF-'));
      expect(tail, contains('%%EOF'));
      expect(bytes.length, greaterThan(10000));
    });

    test('a pontuação de diálogo em português não derruba a exportação',
        () async {
      // As fontes internas do formato PDF só vão até Latin-1: travessão,
      // aspas curvas e reticências estourariam com "Unable to display".
      // É por isso que a Liberation Serif vai embutida.
      final book = Book(
        metadata: const BookMetadata(title: 'Diálogo', author: 'Ana'),
        uuid: 'uuid-2',
        chapters: const [
          BookSection(
            id: 'ch1',
            title: 'Travessão',
            blocks: [
              BookBlock(
                type: BookBlockType.paragraph,
                runs: [
                  TextRun('— Não vá — disse ela. “Fique…” — e ele ficou.'),
                ],
              ),
            ],
          ),
        ],
      );

      expect(() => const PdfExporter().build(book), returnsNormally);
      expect((await const PdfExporter().build(book)).length, greaterThan(1000));
    });

    test('a capa entra como primeira página', () async {
      final semCapa = await const PdfExporter().build(_book);
      final comCapa = await const PdfExporter().build(
        Book(
          metadata: _metadata,
          uuid: 'uuid-1',
          cover: _cover,
          chapters: _book.chapters,
          appendices: _book.appendices,
        ),
      );

      expect(comCapa.length, greaterThan(semCapa.length));
    });
  });
}
