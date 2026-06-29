class CharacterModel {
  final String name;
  final String path;

  const CharacterModel({required this.name, required this.path});

  String get characteristicsPath => '$path/characteristics.md';
  String get evolutionPath => '$path/evolution.md';
}
