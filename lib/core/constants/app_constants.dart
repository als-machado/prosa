class AppConstants {
  AppConstants._();

  static const String appName = 'Prosa';
  static const String appVersion = '0.3.0';
  static const String prosaFileName = '.prosa';

  /// Palavras aceitas pela verificação ortográfica. Fica na raiz do projeto e
  /// é versionado junto com o texto: nome de personagem é do livro, não da
  /// instalação.
  static const String dictionaryFileName = '.prosa_dictionary';

  /// Última configuração de exportação (formato, metadados, seleção, capa).
  /// Fica no projeto porque ISBN e editora são do livro, não da instalação.
  static const String exportConfigFile = '.prosa_export.json';
  static const String chaptersDir = 'chapters';
  static const String charactersDir = 'characters';
  static const String miscDir = 'misc';
  static const String chapterFile = 'chapter.md';
  static const String scenePrefix = 'scene';
  static const String characteristicsFile = 'characteristics.md';
  static const String evolutionFile = 'evolution.md';
  static const String synopsisFile = 'synopsis.md';
  static const String glossaryFile = 'glossary.md';
  static const String notesDir = 'notes';
  static const String locationsDir = 'locations';
  static const String researchDir = 'research';
  static const String timelineDir = 'timeline';
  static const String mindMapsDir = 'mind_maps';
  static const String worldRulesDir = 'world_rules';
}
