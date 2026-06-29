class ProsaProject {
  final String title;
  final String author;
  final String genre;
  final String language;
  final String prosaVersion;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String localPath;
  final String? remoteUrl;

  const ProsaProject({
    required this.title,
    required this.author,
    this.genre = '',
    this.language = 'pt-BR',
    required this.prosaVersion,
    required this.createdAt,
    required this.updatedAt,
    required this.localPath,
    this.remoteUrl,
  });

  factory ProsaProject.create({
    required String title,
    required String author,
    required String localPath,
    String? remoteUrl,
  }) {
    final now = DateTime.now();
    return ProsaProject(
      title: title,
      author: author,
      prosaVersion: '0.1.0',
      createdAt: now,
      updatedAt: now,
      localPath: localPath,
      remoteUrl: remoteUrl,
    );
  }

  Map<String, dynamic> toYaml() => {
        'prosa_version': prosaVersion,
        'title': title,
        'author': author,
        'genre': genre,
        'language': language,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (remoteUrl != null) 'remote_url': remoteUrl,
      };

  factory ProsaProject.fromYaml(Map yaml, String localPath) => ProsaProject(
        title: yaml['title'] ?? '',
        author: yaml['author'] ?? '',
        genre: yaml['genre'] ?? '',
        language: yaml['language'] ?? 'pt-BR',
        prosaVersion: yaml['prosa_version'] ?? '0.1.0',
        createdAt: DateTime.parse(yaml['created_at']),
        updatedAt: DateTime.parse(yaml['updated_at']),
        localPath: localPath,
        remoteUrl: yaml['remote_url'],
      );
}
