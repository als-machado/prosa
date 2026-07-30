import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosa/features/export/domain/book_builder.dart';
import 'package:prosa/features/export/domain/models/book.dart';
import 'package:prosa/features/export/domain/models/book_metadata.dart';
import 'package:prosa/features/export/domain/models/export_selection.dart';
import 'package:prosa/features/projects/presentation/providers/project_tree_provider.dart';

late Directory _root;

/// Monta em disco um projeto Prosa de mentira. Os arquivos são escritos no
/// mesmo formato que o editor salva: uma linha por bloco, sem linha em branco
/// entre parágrafos seguidos.
Future<void> _write(String relativePath, String content) async {
  final file = File('${_root.path}/$relativePath');
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

Future<ProjectTree> _tree() async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container.read(projectTreeProvider(_root.path).future);
}

void main() {
  setUp(() async {
    _root = await Directory.systemTemp.createTemp('prosa_export_test');
  });

  tearDown(() async {
    if (await _root.exists()) await _root.delete(recursive: true);
  });

  group('capítulos', () {
    test('o título de nível 1 vira o título do capítulo e sai do corpo',
        () async {
      await _write(
        'chapters/1 - A partida/chapter.md',
        '# A partida\n'
        'Primeiro parágrafo.\n'
        'Segundo parágrafo.\n',
      );

      final book = await const BookBuilder().build(
        projectPath: _root.path,
        tree: await _tree(),
        selection: ExportSelection(
          chapters: {'${_root.path}/chapters/1 - A partida'},
        ),
        metadata: const BookMetadata(title: 'Livro'),
        uuid: 'uuid',
      );

      expect(book.chapters, hasLength(1));
      expect(book.chapters.single.title, 'A partida');
      // Linhas seguidas são parágrafos separados — se a exportação usasse um
      // parser de Markdown comum, os dois virariam um só.
      expect(
        book.chapters.single.blocks.map((b) => b.plainText),
        ['Primeiro parágrafo.', 'Segundo parágrafo.'],
      );
      expect(
        book.chapters.single.blocks.every(
          (b) => b.type == BookBlockType.paragraph,
        ),
        isTrue,
      );
    });

    test('sem título de nível 1, o nome da pasta vira o título e os títulos '
        'do corpo descem um nível', () async {
      await _write(
        'chapters/2 - O meio/chapter.md',
        '## Uma parte\n'
        'Texto.\n',
      );

      final book = await const BookBuilder().build(
        projectPath: _root.path,
        tree: await _tree(),
        selection:
            ExportSelection(chapters: {'${_root.path}/chapters/2 - O meio'}),
        metadata: const BookMetadata(),
        uuid: 'uuid',
      );

      final chapter = book.chapters.single;
      expect(chapter.title, '2 - O meio');
      expect(chapter.blocks.first.type, BookBlockType.heading);
      expect(chapter.blocks.first.level, 3);
    });

    test('cenas viram um capítulo só, separadas por quebra de cena', () async {
      await _write('chapters/1 - Início/scene 1.md', 'Cena um.\n');
      await _write('chapters/1 - Início/scene 2.md', 'Cena dois.\n');

      final book = await const BookBuilder().build(
        projectPath: _root.path,
        tree: await _tree(),
        selection:
            ExportSelection(chapters: {'${_root.path}/chapters/1 - Início'}),
        metadata: const BookMetadata(),
        uuid: 'uuid',
      );

      final chapter = book.chapters.single;
      expect(chapter.title, '1 - Início');
      expect(
        chapter.blocks.map((b) => b.type),
        [
          BookBlockType.paragraph,
          BookBlockType.divider,
          BookBlockType.paragraph,
        ],
      );
    });

    test('capítulo não escolhido fica de fora', () async {
      await _write('chapters/1 - Um/chapter.md', '# Um\nTexto.\n');
      await _write('chapters/2 - Dois/chapter.md', '# Dois\nTexto.\n');

      final book = await const BookBuilder().build(
        projectPath: _root.path,
        tree: await _tree(),
        selection: ExportSelection(chapters: {'${_root.path}/chapters/2 - Dois'}),
        metadata: const BookMetadata(),
        uuid: 'uuid',
      );

      expect(book.chapters.map((c) => c.title), ['Dois']);
    });

    test('linha em branco não vira parágrafo vazio no livro', () async {
      await _write(
        'chapters/1 - Um/chapter.md',
        '# Um\n'
        'Antes.\n'
        '\n'
        '\n'
        'Depois.\n',
      );

      final book = await const BookBuilder().build(
        projectPath: _root.path,
        tree: await _tree(),
        selection: ExportSelection(chapters: {'${_root.path}/chapters/1 - Um'}),
        metadata: const BookMetadata(),
        uuid: 'uuid',
      );

      expect(
        book.chapters.single.blocks.map((b) => b.plainText),
        ['Antes.', 'Depois.'],
      );
    });

    test('o primeiro parágrafo depois de um título ou de uma quebra de cena '
        'é marcado para sair sem recuo', () async {
      await _write(
        'chapters/1 - Um/chapter.md',
        '# Um\n'
        'Primeiro.\n'
        'Segundo.\n'
        '---\n'
        'Depois da quebra.\n',
      );

      final book = await const BookBuilder().build(
        projectPath: _root.path,
        tree: await _tree(),
        selection: ExportSelection(chapters: {'${_root.path}/chapters/1 - Um'}),
        metadata: const BookMetadata(),
        uuid: 'uuid',
      );

      final blocks = book.chapters.single.blocks;
      expect(blocks[0].startsBlock, isTrue, reason: 'primeiro do capítulo');
      expect(blocks[1].startsBlock, isFalse);
      expect(blocks[2].type, BookBlockType.divider);
      expect(blocks[3].startsBlock, isTrue, reason: 'primeiro depois da quebra');
    });
  });

  group('apêndices', () {
    test('personagem vira um grupo com uma seção por arquivo, sem repetir o '
        'nome no título', () async {
      await _write(
        'characters/Ana/characteristics.md',
        '# Ana — Características\nAlta e calada.\n',
      );
      await _write(
        'characters/Ana/evolution.md',
        '# Ana — Evolução\nAprende a falar.\n',
      );

      final book = await const BookBuilder().build(
        projectPath: _root.path,
        tree: await _tree(),
        selection:
            ExportSelection(characters: {'${_root.path}/characters/Ana'}),
        metadata: const BookMetadata(),
        uuid: 'uuid',
      );

      final group = book.appendices.single;
      expect(group.title, 'Personagens');
      expect(group.subsections.single.title, 'Ana');
      expect(
        group.subsections.single.subsections.map((s) => s.title),
        ['Características', 'Evolução'],
      );
    });

    test('arquivo com só o título não entra no sumário', () async {
      await _write('misc/notes/Vazia.md', '# Vazia\n\n');
      await _write('misc/notes/Cheia.md', '# Cheia\nTem texto.\n');

      final book = await const BookBuilder().build(
        projectPath: _root.path,
        tree: await _tree(),
        selection: ExportSelection(
          miscFiles: {
            '${_root.path}/misc/notes/Vazia.md',
            '${_root.path}/misc/notes/Cheia.md',
          },
        ),
        metadata: const BookMetadata(),
        uuid: 'uuid',
      );

      expect(book.appendices.single.title, 'Notas');
      expect(book.appendices.single.subsections.map((s) => s.title), ['Cheia']);
    });

    test('sinopse e glossário entram como apêndices próprios', () async {
      await _write('misc/synopsis.md', '# Sinopse\nUm resumo.\n');
      await _write('misc/glossary.md', '# Glossário\nPalavras.\n');

      final book = await const BookBuilder().build(
        projectPath: _root.path,
        tree: await _tree(),
        selection: const ExportSelection(synopsis: true, glossary: true),
        metadata: const BookMetadata(),
        uuid: 'uuid',
      );

      expect(book.appendices.map((a) => a.title), ['Sinopse', 'Glossário']);
    });
  });

  test('formatação de linha vira trechos com atributo', () async {
    await _write(
      'chapters/1 - Um/chapter.md',
      '# Um\nUm texto **forte** e *torto*.\n',
    );

    final book = await const BookBuilder().build(
      projectPath: _root.path,
      tree: await _tree(),
      selection: ExportSelection(chapters: {'${_root.path}/chapters/1 - Um'}),
      metadata: const BookMetadata(),
      uuid: 'uuid',
    );

    final runs = book.chapters.single.blocks.single.runs;
    expect(runs.where((r) => r.bold).map((r) => r.text), ['forte']);
    expect(runs.where((r) => r.italic).map((r) => r.text), ['torto']);
  });
}
