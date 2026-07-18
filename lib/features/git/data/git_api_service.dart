import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../settings/domain/models/app_settings.dart';

class RemoteRepo {
  final String name;
  final String cloneUrl;
  final String sshUrl;
  final String description;

  const RemoteRepo({
    required this.name,
    required this.cloneUrl,
    required this.sshUrl,
    this.description = '',
  });
}

class GitApiException implements Exception {
  final String message;
  const GitApiException(this.message);

  @override
  String toString() => message;
}

class GitApiService {
  /// Quantas checagens de .prosa rodam em paralelo. Sequencial, 100 repos
  /// custavam ~100 round-trips enfileirados (dezenas de segundos na Home).
  static const _concurrency = 10;

  Future<List<RemoteRepo>> listProsaRepos(AppSettings settings) async {
    final provider = settings.gitProvider;
    final token = settings.gitToken;
    if (provider == null || token == null) return [];

    if (provider.host == 'github.com') {
      return _githubRepos(token);
    }
    // GitLab.com e servidores personalizados (API compatível com GitLab).
    return _gitlabRepos(token, provider.apiBase);
  }

  /// Filtra [candidates] mantendo só os que têm .prosa, checando em lotes
  /// de [_concurrency] requisições paralelas.
  Future<List<RemoteRepo>> _filterProsa(
    List<(RemoteRepo, Future<bool> Function())> candidates,
  ) async {
    final result = <RemoteRepo>[];
    for (var i = 0; i < candidates.length; i += _concurrency) {
      final batch = candidates.skip(i).take(_concurrency).toList();
      final checks = await Future.wait(batch.map((c) => c.$2()));
      for (var j = 0; j < batch.length; j++) {
        if (checks[j]) result.add(batch[j].$1);
      }
    }
    return result;
  }

  void _throwOnError(http.Response response, String provider) {
    if (response.statusCode == 401) {
      throw GitApiException('Token do $provider inválido ou expirado — verifique em Configurações.');
    }
    if (response.statusCode != 200) {
      throw GitApiException('$provider respondeu ${response.statusCode}.');
    }
  }

  Future<List<RemoteRepo>> _githubRepos(String token) async {
    final response = await http.get(
      Uri.parse('https://api.github.com/user/repos?per_page=100&sort=updated'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github.v3+json',
      },
    );
    _throwOnError(response, 'GitHub');

    final repos = jsonDecode(response.body) as List;
    final candidates = repos.map<(RemoteRepo, Future<bool> Function())>((repo) {
      final owner = repo['owner']['login'] as String;
      final name = repo['name'] as String;
      final r = RemoteRepo(
        name: name,
        cloneUrl: repo['clone_url'] as String,
        sshUrl: repo['ssh_url'] as String,
        description: repo['description'] as String? ?? '',
      );
      return (r, () => _githubHasProsaFile(token, owner, name));
    }).toList();

    return _filterProsa(candidates);
  }

  Future<bool> _githubHasProsaFile(String token, String owner, String repo) async {
    final response = await http.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo/contents/.prosa'),
      headers: {'Authorization': 'Bearer $token'},
    );
    return response.statusCode == 200;
  }

  Future<List<RemoteRepo>> _gitlabRepos(String token, String apiBase) async {
    final response = await http.get(
      Uri.parse('$apiBase/projects?membership=true&per_page=100&order_by=last_activity_at'),
      headers: {'Private-Token': token},
    );
    _throwOnError(response, 'GitLab');

    final repos = jsonDecode(response.body) as List;
    final candidates = repos.map<(RemoteRepo, Future<bool> Function())>((repo) {
      final id = repo['id'] as int;
      final r = RemoteRepo(
        name: repo['name'] as String,
        cloneUrl: repo['http_url_to_repo'] as String,
        sshUrl: repo['ssh_url_to_repo'] as String,
        description: repo['description'] as String? ?? '',
      );
      return (r, () => _gitlabHasProsaFile(token, apiBase, id));
    }).toList();

    return _filterProsa(candidates);
  }

  Future<bool> _gitlabHasProsaFile(String token, String apiBase, int projectId) async {
    // Tenta os nomes de branch default mais comuns.
    for (final branch in ['main', 'master']) {
      final response = await http.get(
        Uri.parse('$apiBase/projects/$projectId/repository/files/.prosa?ref=$branch'),
        headers: {'Private-Token': token},
      );
      if (response.statusCode == 200) return true;
    }
    return false;
  }

  Future<RemoteRepo> createGithubRepo(
    String token,
    String name, {
    String description = '',
    bool private = true,
  }) async {
    final response = await http.post(
      Uri.parse('https://api.github.com/user/repos'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github.v3+json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': name,
        'description': description,
        'private': private,
        'auto_init': false,
      }),
    );
    if (response.statusCode != 201) {
      throw GitApiException('Erro ao criar repositório no GitHub: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return RemoteRepo(
      name: data['name'] as String,
      cloneUrl: data['clone_url'] as String,
      sshUrl: data['ssh_url'] as String,
      description: data['description'] as String? ?? '',
    );
  }

  Future<RemoteRepo> createGitlabRepo(
    String token,
    String name, {
    String description = '',
    bool private = true,
    String apiBase = 'https://gitlab.com/api/v4',
  }) async {
    final response = await http.post(
      Uri.parse('$apiBase/projects'),
      headers: {
        'Private-Token': token,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': name,
        'description': description,
        'visibility': private ? 'private' : 'public',
      }),
    );
    if (response.statusCode != 201) {
      throw GitApiException('Erro ao criar repositório no GitLab: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return RemoteRepo(
      name: data['name'] as String,
      cloneUrl: data['http_url_to_repo'] as String,
      sshUrl: data['ssh_url_to_repo'] as String,
      description: data['description'] as String? ?? '',
    );
  }
}
