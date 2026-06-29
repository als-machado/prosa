import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/prosa_project.dart';

class ProjectService {
  Future<Directory> get defaultProjectsDir async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/Prosa');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<List<ProsaProject>> listLocalProjects() async {
    final base = await defaultProjectsDir;
    final projects = <ProsaProject>[];
    for (final entity in base.listSync()) {
      if (entity is Directory) {
        final prosaFile = File('${entity.path}/${AppConstants.prosaFileName}');
        if (prosaFile.existsSync()) {
          try {
            final yaml = loadYaml(await prosaFile.readAsString()) as Map;
            projects.add(ProsaProject.fromYaml(yaml, entity.path));
          } catch (_) {}
        }
      }
    }
    return projects;
  }

  Future<ProsaProject> createProject({
    required String title,
    required String author,
    String? customPath,
  }) async {
    final base = customPath != null ? Directory(customPath) : await defaultProjectsDir;
    final slug = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');
    final projectDir = Directory('${base.path}/$slug');
    projectDir.createSync(recursive: true);

    _createStructure(projectDir.path);

    final project = ProsaProject.create(
      title: title,
      author: author,
      localPath: projectDir.path,
    );

    await _writeProsaFile(project);
    await Process.run('git', ['init'], workingDirectory: projectDir.path);
    await Process.run('git', ['add', '.'], workingDirectory: projectDir.path);
    await Process.run('git', ['commit', '-m', 'Projeto criado com Prosa'], workingDirectory: projectDir.path);
    return project;
  }

  void _createStructure(String root) {
    final dirs = [
      '${AppConstants.chaptersDir}/1 - Capítulo 1',
      AppConstants.charactersDir,
      '${AppConstants.miscDir}/${AppConstants.notesDir}',
      '${AppConstants.miscDir}/${AppConstants.locationsDir}',
      '${AppConstants.miscDir}/${AppConstants.researchDir}',
      '${AppConstants.miscDir}/${AppConstants.timelineDir}',
      '${AppConstants.miscDir}/${AppConstants.mindMapsDir}',
      '${AppConstants.miscDir}/${AppConstants.worldRulesDir}',
    ];
    for (final d in dirs) {
      Directory('$root/$d').createSync(recursive: true);
    }

    File('$root/${AppConstants.chaptersDir}/1 - Capítulo 1/${AppConstants.chapterFile}')
        .writeAsStringSync('# Capítulo 1\n\n');
    File('$root/${AppConstants.miscDir}/${AppConstants.synopsisFile}')
        .writeAsStringSync('# Sinopse\n\n');
    File('$root/${AppConstants.miscDir}/${AppConstants.glossaryFile}')
        .writeAsStringSync('# Glossário\n\n');
  }

  Future<void> _writeProsaFile(ProsaProject project) async {
    final file = File('${project.localPath}/${AppConstants.prosaFileName}');
    final yaml = project.toYaml().entries
        .map((e) => '${e.key}: ${_yamlValue(e.value)}')
        .join('\n');
    await file.writeAsString('$yaml\n');
  }

  String _yamlValue(dynamic v) {
    if (v == null) return 'null';
    if (v is String) return '"$v"';
    return v.toString();
  }

  Future<ProsaProject?> loadProject(String path) async {
    final file = File('$path/${AppConstants.prosaFileName}');
    if (!file.existsSync()) return null;
    final yaml = loadYaml(await file.readAsString()) as Map;
    return ProsaProject.fromYaml(yaml, path);
  }
}
