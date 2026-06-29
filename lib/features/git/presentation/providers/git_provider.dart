import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/git_service.dart';
import '../../data/ssh_service.dart';
import '../../../projects/presentation/providers/projects_provider.dart';

final gitServiceProvider = Provider((_) => GitService());
final sshServiceProvider = Provider((_) => SshService());

final currentBranchProvider = FutureProvider<String?>((ref) async {
  final project = ref.watch(activeProjectProvider);
  if (project == null) return null;
  final git = ref.read(gitServiceProvider);
  return git.currentBranch(project.localPath);
});

final branchesProvider = FutureProvider<List<String>>((ref) async {
  final project = ref.watch(activeProjectProvider);
  if (project == null) return [];
  final git = ref.read(gitServiceProvider);
  return git.branches(project.localPath);
});

final commitLogProvider = FutureProvider<List<CommitEntry>>((ref) async {
  final project = ref.watch(activeProjectProvider);
  if (project == null) return [];
  final git = ref.read(gitServiceProvider);
  return git.log(project.localPath);
});

final hasKeyPairProvider = FutureProvider<bool>((ref) async {
  final ssh = ref.read(sshServiceProvider);
  return ssh.hasKeyPair;
});

final publicKeyProvider = FutureProvider<String?>((ref) async {
  final ssh = ref.read(sshServiceProvider);
  return ssh.readPublicKey();
});
