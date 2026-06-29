class GitProvider {
  final String name;
  final String host;
  final String apiBase;
  final String sshUser;

  const GitProvider({
    required this.name,
    required this.host,
    required this.apiBase,
    required this.sshUser,
  });

  static const github = GitProvider(
    name: 'GitHub',
    host: 'github.com',
    apiBase: 'https://api.github.com',
    sshUser: 'git',
  );

  static const gitlab = GitProvider(
    name: 'GitLab',
    host: 'gitlab.com',
    apiBase: 'https://gitlab.com/api/v4',
    sshUser: 'git',
  );

  static GitProvider custom({required String host, String? apiBase, String sshUser = 'git'}) =>
      GitProvider(
        name: host,
        host: host,
        apiBase: apiBase ?? 'https://$host/api/v4',
        sshUser: sshUser,
      );
}

class AppSettings {
  final bool darkMode;
  final String editorFont;
  final double editorFontSize;
  final GitProvider? gitProvider;
  final String? gitUsername;
  final String? gitToken;
  final String? localProjectsPath;

  const AppSettings({
    this.darkMode = false,
    this.editorFont = 'Lora',
    this.editorFontSize = 16.0,
    this.gitProvider,
    this.gitUsername,
    this.gitToken,
    this.localProjectsPath,
  });

  AppSettings copyWith({
    bool? darkMode,
    String? editorFont,
    double? editorFontSize,
    GitProvider? gitProvider,
    String? gitUsername,
    String? gitToken,
    String? localProjectsPath,
  }) =>
      AppSettings(
        darkMode: darkMode ?? this.darkMode,
        editorFont: editorFont ?? this.editorFont,
        editorFontSize: editorFontSize ?? this.editorFontSize,
        gitProvider: gitProvider ?? this.gitProvider,
        gitUsername: gitUsername ?? this.gitUsername,
        gitToken: gitToken ?? this.gitToken,
        localProjectsPath: localProjectsPath ?? this.localProjectsPath,
      );

  Map<String, dynamic> toMap() => {
        'darkMode': darkMode,
        'editorFont': editorFont,
        'editorFontSize': editorFontSize,
        'gitProviderHost': gitProvider?.host,
        'gitProviderName': gitProvider?.name,
        'gitProviderApiBase': gitProvider?.apiBase,
        'gitProviderSshUser': gitProvider?.sshUser,
        'gitUsername': gitUsername,
        'gitToken': gitToken,
        'localProjectsPath': localProjectsPath,
      };

  factory AppSettings.fromMap(Map<String, dynamic> m) {
    final host = m['gitProviderHost'] as String?;
    GitProvider? provider;
    if (host != null) {
      if (host == 'github.com') {
        provider = GitProvider.github;
      } else if (host == 'gitlab.com') {
        provider = GitProvider.gitlab;
      } else {
        provider = GitProvider.custom(
          host: host,
          apiBase: m['gitProviderApiBase'] as String?,
          sshUser: m['gitProviderSshUser'] as String? ?? 'git',
        );
      }
    }
    return AppSettings(
      darkMode: m['darkMode'] as bool? ?? false,
      editorFont: m['editorFont'] as String? ?? 'Georgia',
      editorFontSize: (m['editorFontSize'] as num?)?.toDouble() ?? 16.0,
      gitProvider: provider,
      gitUsername: m['gitUsername'] as String?,
      gitToken: m['gitToken'] as String?,
      localProjectsPath: m['localProjectsPath'] as String?,
    );
  }
}
