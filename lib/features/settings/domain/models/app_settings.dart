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
  final int editorTabSize;
  final double editorMarginHorizontal;
  final bool spellcheckEnabled;

  /// Idioma da verificação ortográfica escolhido pelo usuário. Null significa
  /// "usar o idioma do projeto", que é o campo `language` do `.prosa`.
  final String? spellcheckLanguage;

  final GitProvider? gitProvider;
  final String? gitUsername;
  final String? gitToken;
  final String? localProjectsPath;

  const AppSettings({
    this.darkMode = false,
    this.editorFont = 'Lora',
    this.editorFontSize = 16.0,
    this.editorTabSize = 4,
    this.editorMarginHorizontal = 80.0,
    this.spellcheckEnabled = true,
    this.spellcheckLanguage,
    this.gitProvider,
    this.gitUsername,
    this.gitToken,
    this.localProjectsPath,
  });

  /// Sentinela para distinguir "não mexer neste campo" de "voltar para null".
  /// Sem ela, o `??` do copyWith não conseguiria devolver spellcheckLanguage
  /// ao padrão (seguir o idioma do projeto).
  static const _keep = Object();

  AppSettings copyWith({
    bool? darkMode,
    String? editorFont,
    double? editorFontSize,
    int? editorTabSize,
    double? editorMarginHorizontal,
    bool? spellcheckEnabled,
    Object? spellcheckLanguage = _keep,
    GitProvider? gitProvider,
    String? gitUsername,
    String? gitToken,
    String? localProjectsPath,
  }) =>
      AppSettings(
        darkMode: darkMode ?? this.darkMode,
        editorFont: editorFont ?? this.editorFont,
        editorFontSize: editorFontSize ?? this.editorFontSize,
        editorTabSize: editorTabSize ?? this.editorTabSize,
        editorMarginHorizontal: editorMarginHorizontal ?? this.editorMarginHorizontal,
        spellcheckEnabled: spellcheckEnabled ?? this.spellcheckEnabled,
        spellcheckLanguage: spellcheckLanguage == _keep
            ? this.spellcheckLanguage
            : spellcheckLanguage as String?,
        gitProvider: gitProvider ?? this.gitProvider,
        gitUsername: gitUsername ?? this.gitUsername,
        gitToken: gitToken ?? this.gitToken,
        localProjectsPath: localProjectsPath ?? this.localProjectsPath,
      );

  /// O gitToken NÃO entra aqui de propósito: ele é persistido à parte no
  /// armazenamento seguro do sistema (Secret Service via
  /// flutter_secure_storage), nunca em texto claro no shared_preferences.
  Map<String, dynamic> toMap() => {
        'darkMode': darkMode,
        'editorFont': editorFont,
        'editorFontSize': editorFontSize,
        'editorTabSize': editorTabSize,
        'editorMarginHorizontal': editorMarginHorizontal,
        'spellcheckEnabled': spellcheckEnabled,
        'spellcheckLanguage': spellcheckLanguage,
        'gitProviderHost': gitProvider?.host,
        'gitProviderName': gitProvider?.name,
        'gitProviderApiBase': gitProvider?.apiBase,
        'gitProviderSshUser': gitProvider?.sshUser,
        'gitUsername': gitUsername,
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
      editorFont: m['editorFont'] as String? ?? 'Lora',
      editorFontSize: (m['editorFontSize'] as num?)?.toDouble() ?? 16.0,
      editorTabSize: (m['editorTabSize'] as num?)?.toInt() ?? 4,
      editorMarginHorizontal: (m['editorMarginHorizontal'] as num?)?.toDouble() ?? 80.0,
      spellcheckEnabled: m['spellcheckEnabled'] as bool? ?? true,
      spellcheckLanguage: m['spellcheckLanguage'] as String?,
      gitProvider: provider,
      gitUsername: m['gitUsername'] as String?,
      gitToken: m['gitToken'] as String?,
      localProjectsPath: m['localProjectsPath'] as String?,
    );
  }
}
