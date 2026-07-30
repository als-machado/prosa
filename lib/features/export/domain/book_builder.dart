import 'dart:io';

import '../../../core/constants/app_constants.dart';
import '../../editor/domain/prosa_markdown.dart';
import '../../projects/presentation/providers/project_tree_provider.dart';
import 'document_to_blocks.dart';
import 'models/book.dart';
import 'models/book_metadata.dart';
import 'models/export_selection.dart';

/// Monta o [Book] a partir dos arquivos do projeto.
///
/// É o único lugar que lê o disco na exportação: os exportadores recebem o
/// livro pronto e só o serializam. Assim DOCX, PDF e companhia herdam de
/// graça as decisões editoriais tomadas aqui — de onde vem o título de cada
/// capítulo, o que vira apêndice, o que é quebra de cena.
class BookBuilder {
  const BookBuilder();

  static const _miscLabels = {
    AppConstants.notesDir: 'Notas',
    AppConstants.locationsDir: 'Locais',
    AppConstants.researchDir: 'Pesquisa',
    AppConstants.timelineDir: 'Linha do tempo',
    AppConstants.worldRulesDir: 'Regras do mundo',
  };

  Future<Book> build({
    required String projectPath,
    required ProjectTree tree,
    required ExportSelection selection,
    required BookMetadata metadata,
    required String uuid,
    BookCover? cover,
  }) async {
    final chapters = <BookSection>[];
    for (final chapter in tree.chapters) {
      if (!selection.chapters.contains(chapter.dirPath)) continue;
      chapters.add(
        await _chapterSection(chapter, 'ch${chapters.length + 1}'),
      );
    }

    return Book(
      metadata: metadata,
      uuid: uuid,
      cover: cover,
      chapters: chapters,
      appendices: await _appendices(projectPath, tree, selection),
    );
  }

  // ---------------------------------------------------------------- capítulos

  Future<BookSection> _chapterSection(ChapterNode chapter, String id) async {
    if (chapter.hasScenes) {
      final blocks = <BookBlock>[];
      for (final scene in chapter.scenes) {
        final sceneBlocks = await _readBlocks(scene.path);
        if (sceneBlocks.isEmpty) continue;
        // Cenas seguidas são separadas por uma quebra, e não por um título:
        // o nome do arquivo ("scene 2") é organização do autor, não do livro.
        if (blocks.isNotEmpty) {
          blocks.add(const BookBlock(type: BookBlockType.divider));
        }
        blocks.addAll(sceneBlocks);
      }
      // O título vem da pasta, então nenhum título do corpo foi consumido e
      // todos descem um nível para caber embaixo dele.
      return BookSection(
        id: id,
        title: chapter.name,
        blocks: _markFirstParagraphs(_shiftHeadings(blocks, 1)),
      );
    }

    final blocks = await _readBlocks(chapter.chapterFilePath);
    final (promoted, rest) = _promoteTitle(blocks);
    return BookSection(
      id: id,
      title: promoted ?? chapter.name,
      blocks: _markFirstParagraphs(_shiftHeadings(rest, promoted == null ? 1 : 0)),
    );
  }

  // ---------------------------------------------------------------- apêndices

  Future<List<BookSection>> _appendices(
    String projectPath,
    ProjectTree tree,
    ExportSelection selection,
  ) async {
    final appendices = <BookSection>[];
    String nextId() => 'ap${appendices.length + 1}';

    if (selection.synopsis) {
      final section = await _fileSection(
        id: nextId(),
        path: '$projectPath/${AppConstants.miscDir}/${AppConstants.synopsisFile}',
        fallbackTitle: 'Sinopse',
        depth: 0,
      );
      if (section != null) appendices.add(section);
    }

    if (selection.glossary) {
      final section = await _fileSection(
        id: nextId(),
        path: '$projectPath/${AppConstants.miscDir}/${AppConstants.glossaryFile}',
        fallbackTitle: 'Glossário',
        depth: 0,
      );
      if (section != null) appendices.add(section);
    }

    final characters = tree.characters
        .where((c) => selection.characters.contains(c.dirPath))
        .toList();
    if (characters.isNotEmpty) {
      final groupId = nextId();
      final subsections = <BookSection>[];
      for (final character in characters) {
        final section =
            await _characterSection(character, '${groupId}_${subsections.length + 1}');
        if (section != null) subsections.add(section);
      }
      if (subsections.isNotEmpty) {
        appendices.add(
          BookSection(id: groupId, title: 'Personagens', subsections: subsections),
        );
      }
    }

    for (final misc in tree.miscSections) {
      final files =
          misc.files.where((f) => selection.miscFiles.contains(f.path)).toList();
      if (files.isEmpty) continue;

      final groupId = nextId();
      final subsections = <BookSection>[];
      for (final file in files) {
        final section = await _fileSection(
          id: '${groupId}_${subsections.length + 1}',
          path: file.path,
          fallbackTitle: file.name,
          depth: 1,
        );
        if (section != null) subsections.add(section);
      }
      if (subsections.isEmpty) continue;

      appendices.add(
        BookSection(
          id: groupId,
          title: _miscLabels[misc.dirName] ?? misc.dirName,
          subsections: subsections,
        ),
      );
    }

    return appendices;
  }

  Future<BookSection?> _characterSection(
    CharacterNode character,
    String id,
  ) async {
    final parts = <BookSection>[];
    for (final (file, label) in [
      (AppConstants.characteristicsFile, 'Características'),
      (AppConstants.evolutionFile, 'Evolução'),
    ]) {
      final section = await _fileSection(
        id: '${id}_${parts.length + 1}',
        path: '${character.dirPath}/$file',
        fallbackTitle: label,
        depth: 2,
        // Os arquivos criados pelo Prosa começam com "# Nome — Características";
        // dentro da seção do personagem o nome já está no título de cima.
        stripPrefix: character.name,
        prefixFallback: label,
      );
      if (section != null) parts.add(section);
    }
    if (parts.isEmpty) return null;
    return BookSection(id: id, title: character.name, subsections: parts);
  }

  Future<BookSection?> _fileSection({
    required String id,
    required String path,
    required String fallbackTitle,
    required int depth,
    String? stripPrefix,
    String? prefixFallback,
  }) async {
    final blocks = await _readBlocks(path);
    if (blocks.isEmpty) return null;

    final (promoted, rest) = _promoteTitle(blocks);
    // Arquivo que só tem o título — criado e nunca preenchido — não vira
    // uma entrada vazia no sumário do livro.
    if (rest.isEmpty) return null;

    var title = promoted ?? fallbackTitle;
    if (stripPrefix != null) {
      title = _withoutPrefix(title, stripPrefix, prefixFallback ?? fallbackTitle);
    }

    return BookSection(
      id: id,
      title: title,
      blocks: _markFirstParagraphs(
        _shiftHeadings(rest, promoted == null ? depth + 1 : depth),
      ),
    );
  }

  // ------------------------------------------------------------------ leitura

  Future<List<BookBlock>> _readBlocks(String path) async {
    final file = File(path);
    if (!await file.exists()) return const [];

    final content = await file.readAsString();
    if (content.trim().isEmpty) return const [];

    final blocks = documentToBookBlocks(markdownToEditorDocument(content));
    // Linha em branco é parágrafo vazio no formato do Prosa. Em livro o
    // espaço entre parágrafos vem do CSS/estilo, então ela não vira nada.
    return blocks
        .where((b) => !b.isBlank)
        .map((b) => _resolveImage(b, file.parent.path))
        .toList();
  }

  /// Caminho relativo de imagem é relativo ao arquivo que a citou; guardar o
  /// caminho absoluto aqui deixa o exportador só com o trabalho de embutir.
  BookBlock _resolveImage(BookBlock block, String baseDir) {
    final url = block.imageUrl;
    if (block.type != BookBlockType.image || url == null) return block;
    if (url.startsWith('http://') || url.startsWith('https://')) return block;
    if (url.startsWith('/')) return block;
    return BookBlock(type: BookBlockType.image, imageUrl: '$baseDir/$url');
  }

  // ------------------------------------------------------------ ajustes finos

  /// Tira o título de nível 1 que abre o arquivo e devolve como título da
  /// seção — é o mesmo texto, e repetido ele apareceria duas vezes seguidas.
  (String?, List<BookBlock>) _promoteTitle(List<BookBlock> blocks) {
    if (blocks.isEmpty) return (null, blocks);
    final first = blocks.first;
    if (first.type != BookBlockType.heading || first.level != 1) {
      return (null, blocks);
    }
    final title = first.plainText.trim();
    if (title.isEmpty) return (null, blocks);
    return (title, blocks.sublist(1));
  }

  List<BookBlock> _shiftHeadings(List<BookBlock> blocks, int by) {
    if (by == 0) return blocks;
    return blocks
        .map(
          (b) => b.type == BookBlockType.heading
              ? b.copyWith(level: (b.level + by).clamp(1, 6))
              : b,
        )
        .toList();
  }

  /// Marca o primeiro parágrafo de cada trecho — depois de um título ou de uma
  /// quebra de cena. Em livro ele não leva recuo de primeira linha.
  List<BookBlock> _markFirstParagraphs(List<BookBlock> blocks) {
    var atStart = true;
    return blocks.map((block) {
      switch (block.type) {
        case BookBlockType.heading:
        case BookBlockType.divider:
          atStart = true;
          return block;
        case BookBlockType.paragraph:
          if (!atStart) return block;
          atStart = false;
          return block.copyWith(startsBlock: true);
        default:
          atStart = false;
          return block;
      }
    }).toList();
  }

  String _withoutPrefix(String title, String prefix, String fallback) {
    for (final separator in const [' — ', ' – ', ' - ', ': ']) {
      final full = '$prefix$separator';
      if (title.startsWith(full)) {
        final rest = title.substring(full.length).trim();
        return rest.isEmpty ? fallback : rest;
      }
    }
    return title;
  }
}
