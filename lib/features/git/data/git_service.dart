import 'dart:io';

class GitException implements Exception {
  final String command;
  final String message;
  const GitException(this.command, this.message);

  @override
  String toString() => 'git $command: $message';
}

class GitService {
  Map<String, String>? _sshEnv(String? sshKeyPath) => sshKeyPath != null
      ? {
          'GIT_SSH_COMMAND':
              'ssh -i "$sshKeyPath" -o StrictHostKeyChecking=accept-new -o BatchMode=yes'
        }
      : null;

  /// Roda git e lança [GitException] em exit code != 0 — falhas de
  /// commit/checkout silenciosas deixavam a UI reportar sucesso falso.
  Future<ProcessResult> _run(
    List<String> args, {
    String? workingDir,
    String? sshKeyPath,
  }) async {
    final r = await Process.run(
      'git',
      args,
      workingDirectory: workingDir,
      environment: _sshEnv(sshKeyPath),
    );
    if (r.exitCode != 0) {
      final stderr = (r.stderr as String).trim();
      final stdout = (r.stdout as String).trim();
      throw GitException(args.first, stderr.isNotEmpty ? stderr : stdout);
    }
    return r;
  }

  Future<void> init(String dir) async {
    await _run(['init'], workingDir: dir);
  }

  Future<String> status(String repoPath) async {
    final r = await _run(['status', '--short'], workingDir: repoPath);
    return r.stdout as String;
  }

  Future<void> add(String repoPath, [String path = '.']) async {
    await _run(['add', path], workingDir: repoPath);
  }

  Future<void> commit(String repoPath, String message) async {
    await _run(['commit', '-m', message], workingDir: repoPath);
  }

  Future<String> push(String repoPath, {
    String remote = 'origin',
    String? branch,
    String? sshKeyPath,
    bool setUpstream = false,
  }) async {
    final args = ['push'];
    if (setUpstream) args.add('--set-upstream');
    args.add(remote);
    if (branch != null) args.add(branch);
    final r = await _run(args, workingDir: repoPath, sshKeyPath: sshKeyPath);
    return r.stdout as String;
  }

  Future<void> pull(String repoPath, {String remote = 'origin', String? sshKeyPath}) async {
    await _run(['pull', remote], workingDir: repoPath, sshKeyPath: sshKeyPath);
  }

  Future<List<String>> branches(String repoPath) async {
    final r = await _run(['branch', '-a'], workingDir: repoPath);
    return (r.stdout as String)
        .split('\n')
        .map((l) => l.trim().replaceFirst('* ', ''))
        .where((l) => l.isNotEmpty)
        .toList();
  }

  Future<String> currentBranch(String repoPath) async {
    final r = await _run(['branch', '--show-current'], workingDir: repoPath);
    return (r.stdout as String).trim();
  }

  Future<void> checkout(String repoPath, String ref) async {
    await _run(['checkout', ref], workingDir: repoPath);
  }

  Future<void> createBranch(String repoPath, String name) async {
    await _run(['checkout', '-b', name], workingDir: repoPath);
  }

  Future<List<CommitEntry>> log(String repoPath) async {
    const sep = '|PROSA|';
    // Repositório sem commits faz `git log` sair com 128 — lista vazia é a
    // resposta correta, não um erro.
    final r = await Process.run(
      'git',
      ['log', '--format=%H$sep%s$sep%an$sep%ai'],
      workingDirectory: repoPath,
    );
    if (r.exitCode != 0) return [];
    return (r.stdout as String)
        .split('\n')
        .where((l) => l.isNotEmpty)
        .map((l) {
          final parts = l.split(sep);
          return CommitEntry(
            hash: parts[0],
            message: parts.length > 1 ? parts[1] : '',
            author: parts.length > 2 ? parts[2] : '',
            date: parts.length > 3 ? DateTime.tryParse(parts[3]) : null,
          );
        })
        .toList();
  }

  Future<void> addRemote(String repoPath, String url, {String name = 'origin'}) async {
    await _run(['remote', 'add', name, url], workingDir: repoPath);
  }

  Future<bool> hasRemote(String repoPath) async {
    final r = await _run(['remote'], workingDir: repoPath);
    return (r.stdout as String).trim().isNotEmpty;
  }

  Future<void> clone(String url, String destination, {String? sshKeyPath}) async {
    final r = await Process.run(
      'git',
      ['clone', url, destination],
      environment: _sshEnv(sshKeyPath),
    );
    if (r.exitCode != 0) {
      throw GitException('clone', (r.stderr as String).trim());
    }
  }
}

class CommitEntry {
  final String hash;
  final String message;
  final String author;
  final DateTime? date;

  const CommitEntry({
    required this.hash,
    required this.message,
    required this.author,
    this.date,
  });
}
