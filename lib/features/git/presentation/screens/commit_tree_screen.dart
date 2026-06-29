import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/git_service.dart';
import '../providers/git_provider.dart';
import '../../../projects/presentation/providers/projects_provider.dart';

class CommitTreeScreen extends ConsumerWidget {
  const CommitTreeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commits = ref.watch(commitLogProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de commits')),
      body: commits.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (list) {
          if (list.isEmpty) return const Center(child: Text('Nenhum commit encontrado'));
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) => _CommitTile(commit: list[i]),
          );
        },
      ),
    );
  }
}

class _CommitTile extends ConsumerWidget {
  final CommitEntry commit;
  const _CommitTile({required this.commit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: CircleAvatar(
        radius: 14,
        child: Text(commit.hash.substring(0, 2), style: const TextStyle(fontSize: 10)),
      ),
      title: Text(commit.message),
      subtitle: Text(
        '${commit.author} · ${commit.date != null ? _formatDate(commit.date!) : ""}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: TextButton(
        child: const Text('Checkout'),
        onPressed: () => _checkout(context, ref),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _checkout(BuildContext context, WidgetRef ref) async {
    final project = ref.read(activeProjectProvider);
    if (project == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Fazer checkout'),
        content: Text('Ir para o commit "${commit.message}"?\n\nO estado atual não salvo será perdido.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmed != true) return;
    final git = ref.read(gitServiceProvider);
    await git.checkout(project.localPath, commit.hash);
    if (context.mounted) context.go('/editor');
  }
}
