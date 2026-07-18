import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';

class SceneNode {
  final String name;
  final String path;
  const SceneNode({required this.name, required this.path});
}

class ChapterNode {
  final String name;
  final String dirPath;
  final String chapterFilePath;
  final bool hasScenes;
  final List<SceneNode> scenes;

  const ChapterNode({
    required this.name,
    required this.dirPath,
    required this.chapterFilePath,
    required this.hasScenes,
    required this.scenes,
  });
}

class CharacterNode {
  final String name;
  final String dirPath;
  const CharacterNode({required this.name, required this.dirPath});
}

/// Uma subpasta de misc/ (notas, locais, pesquisa…) com seus arquivos .md.
class MiscSection {
  final String dirName;
  final String dirPath;
  final List<SceneNode> files;
  const MiscSection({required this.dirName, required this.dirPath, required this.files});
}

class ProjectTree {
  final List<ChapterNode> chapters;
  final List<CharacterNode> characters;
  final List<MiscSection> miscSections;
  const ProjectTree({
    required this.chapters,
    required this.characters,
    required this.miscSections,
  });
}

/// Capítulos e cenas são ordenados pelo número no início do nome
/// ("2 - Meio" antes de "10 - Final"); sem número, vão para o fim
/// em ordem alfabética.
int _leadingNumber(String name) {
  final match = RegExp(r'\d+').firstMatch(name);
  return match != null ? int.parse(match.group(0)!) : 1 << 30;
}

int _byNumberThenName(String a, String b) {
  final cmp = _leadingNumber(a).compareTo(_leadingNumber(b));
  return cmp != 0 ? cmp : a.compareTo(b);
}

String _basename(String path) => path.split('/').last;

final projectTreeProvider =
    FutureProvider.family<ProjectTree, String>((ref, projectPath) async {
  final chaptersDir = Directory('$projectPath/${AppConstants.chaptersDir}');
  final charactersDir = Directory('$projectPath/${AppConstants.charactersDir}');

  final chapters = <ChapterNode>[];
  if (await chaptersDir.exists()) {
    final dirs =
        (await chaptersDir.list().toList()).whereType<Directory>().toList();
    dirs.sort((a, b) => _byNumberThenName(_basename(a.path), _basename(b.path)));

    for (final dir in dirs) {
      final name = _basename(dir.path);
      final chapterFilePath = '${dir.path}/${AppConstants.chapterFile}';
      final hasChapterFile = await File(chapterFilePath).exists();

      final sceneFiles = (await dir.list().toList())
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.md') && !f.path.endsWith(AppConstants.chapterFile))
          .toList();
      sceneFiles
          .sort((a, b) => _byNumberThenName(_basename(a.path), _basename(b.path)));

      chapters.add(ChapterNode(
        name: name,
        dirPath: dir.path,
        chapterFilePath: chapterFilePath,
        hasScenes: !hasChapterFile && sceneFiles.isNotEmpty,
        scenes: sceneFiles
            .map((f) => SceneNode(
                  name: _basename(f.path).replaceAll('.md', ''),
                  path: f.path,
                ))
            .toList(),
      ));
    }
  }

  final characters = <CharacterNode>[];
  if (await charactersDir.exists()) {
    final dirs =
        (await charactersDir.list().toList()).whereType<Directory>().toList();
    dirs.sort((a, b) => _basename(a.path).compareTo(_basename(b.path)));
    characters.addAll(
      dirs.map((d) => CharacterNode(name: _basename(d.path), dirPath: d.path)),
    );
  }

  const miscDirNames = [
    AppConstants.notesDir,
    AppConstants.locationsDir,
    AppConstants.researchDir,
    AppConstants.timelineDir,
    AppConstants.worldRulesDir,
  ];
  final miscSections = <MiscSection>[];
  for (final dirName in miscDirNames) {
    final dir = Directory('$projectPath/${AppConstants.miscDir}/$dirName');
    final files = <SceneNode>[];
    if (await dir.exists()) {
      final mdFiles = (await dir.list().toList())
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList();
      mdFiles.sort((a, b) => _basename(a.path).compareTo(_basename(b.path)));
      files.addAll(mdFiles.map((f) => SceneNode(
            name: _basename(f.path).replaceAll('.md', ''),
            path: f.path,
          )));
    }
    miscSections.add(MiscSection(dirName: dirName, dirPath: dir.path, files: files));
  }

  return ProjectTree(
    chapters: chapters,
    characters: characters,
    miscSections: miscSections,
  );
});
