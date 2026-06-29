import 'dart:io';

class GitService {
  Future<ProcessResult> _run(List<String> args, {String? workingDir}) async {
    final result = await Process.run('git', args, workingDirectory: workingDir);
    return result;
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

  Future<void> push(String repoPath, {String remote = 'origin', String? branch}) async {
    final args = ['push', remote];
    if (branch != null) args.add(branch);
    await _run(args, workingDir: repoPath);
  }

  Future<void> pull(String repoPath, {String remote = 'origin'}) async {
    await _run(['pull', remote], workingDir: repoPath);
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
    final sep = '|PROSA|';
    final r = await _run(
      ['log', '--oneline', '--format=%H$sep%s$sep%an$sep%ai'],
      workingDir: repoPath,
    );
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

  Future<List<String>> remoteRepos(String sshHost, String sshUser) async {
    return [];
  }

  Future<void> clone(String url, String destination, {String? sshKeyPath}) async {
    final env = sshKeyPath != null
        ? {'GIT_SSH_COMMAND': 'ssh -i $sshKeyPath -o StrictHostKeyChecking=no'}
        : null;
    await Process.run('git', ['clone', url, destination], environment: env);
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
