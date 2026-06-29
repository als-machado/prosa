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

class GitApiService {
  Future<List<RemoteRepo>> listProsaRepos(AppSettings settings) async {
    final provider = settings.gitProvider;
    final token = settings.gitToken;
    final username = settings.gitUsername;
    if (provider == null || token == null || username == null) return [];

    try {
      if (provider.host == 'github.com') {
        return await _githubRepos(token);
      } else if (provider.host == 'gitlab.com') {
        return await _gitlabRepos(token);
      }
    } catch (_) {}
    return [];
  }

  Future<List<RemoteRepo>> _githubRepos(String token) async {
    final response = await http.get(
      Uri.parse('https://api.github.com/user/repos?per_page=100&sort=updated'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github.v3+json',
      },
    );
    if (response.statusCode != 200) return [];

    final repos = jsonDecode(response.body) as List;
    final prosaRepos = <RemoteRepo>[];

    for (final repo in repos) {
      final owner = repo['owner']['login'] as String;
      final name = repo['name'] as String;
      final hasProsa = await _githubHasProsaFile(token, owner, name);
      if (hasProsa) {
        prosaRepos.add(RemoteRepo(
          name: name,
          cloneUrl: repo['clone_url'] as String,
          sshUrl: repo['ssh_url'] as String,
          description: repo['description'] as String? ?? '',
        ));
      }
    }
    return prosaRepos;
  }

  Future<bool> _githubHasProsaFile(String token, String owner, String repo) async {
    final response = await http.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo/contents/.prosa'),
      headers: {'Authorization': 'Bearer $token'},
    );
    return response.statusCode == 200;
  }

  Future<List<RemoteRepo>> _gitlabRepos(String token) async {
    final response = await http.get(
      Uri.parse('https://gitlab.com/api/v4/projects?membership=true&per_page=100&order_by=last_activity_at'),
      headers: {'Private-Token': token},
    );
    if (response.statusCode != 200) return [];

    final repos = jsonDecode(response.body) as List;
    final prosaRepos = <RemoteRepo>[];

    for (final repo in repos) {
      final id = repo['id'] as int;
      final hasProsa = await _gitlabHasProsaFile(token, id);
      if (hasProsa) {
        prosaRepos.add(RemoteRepo(
          name: repo['name'] as String,
          cloneUrl: repo['http_url_to_repo'] as String,
          sshUrl: repo['ssh_url_to_repo'] as String,
          description: repo['description'] as String? ?? '',
        ));
      }
    }
    return prosaRepos;
  }

  Future<RemoteRepo?> createGithubRepo(
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
      throw Exception('Erro ao criar repositório: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return RemoteRepo(
      name: data['name'] as String,
      cloneUrl: data['clone_url'] as String,
      sshUrl: data['ssh_url'] as String,
      description: data['description'] as String? ?? '',
    );
  }

  Future<bool> _gitlabHasProsaFile(String token, int projectId) async {
    final response = await http.get(
      Uri.parse('https://gitlab.com/api/v4/projects/$projectId/repository/files/.prosa?ref=main'),
      headers: {'Private-Token': token},
    );
    return response.statusCode == 200;
  }
}
