class ChapterModel {
  final int number;
  final String title;
  final String path;
  final List<SceneModel> scenes;
  final bool hasScenes;

  const ChapterModel({
    required this.number,
    required this.title,
    required this.path,
    required this.scenes,
    required this.hasScenes,
  });

  String get displayName => title.isNotEmpty ? '$number - $title' : '$number';
}

class SceneModel {
  final int number;
  final String path;

  const SceneModel({required this.number, required this.path});

  String get fileName => 'scene $number.md';
}
