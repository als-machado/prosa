import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/git_provider.dart';
import '../../../projects/presentation/providers/projects_provider.dart';

class BranchDialog extends ConsumerStatefulWidget {
  const BranchDialog({super.key});

  @override
  ConsumerState<BranchDialog> createState() => _BranchDialogState();
}

class _BranchDialogState extends ConsumerState<BranchDialog> {
  final _newBranchCtrl = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _newBranchCtrl.dispose();
    super.dispose();
  }

  Future<void> _switchBranch(String branch) async {
    final project = ref.read(activeProjectProvider);
    if (project == null) return;
    final git = ref.read(gitServiceProvider);
    await git.checkout(project.localPath, branch);
    ref.invalidate(currentBranchProvider);
    ref.invalidate(branchesProvider);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _createBranch() async {
    final name = _newBranchCtrl.text.trim();
    if (name.isEmpty) return;
    final project = ref.read(activeProjectProvider);
    if (project == null) return;
    final git = ref.read(gitServiceProvider);
    await git.createBranch(project.localPath, name);
    ref.invalidate(currentBranchProvider);
    ref.invalidate(branchesProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final branches = ref.watch(branchesProvider);
    final current = ref.watch(currentBranchProvider).valueOrNull ?? '';

    return AlertDialog(
      title: const Text('Gerenciar branches'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Branch atual: $current',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            branches.when(
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('Erro: $e'),
              data: (list) => ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView(
                  shrinkWrap: true,
                  children: list.map((b) {
                    final isCurrent = b == current || b.endsWith('/$current');
                    return ListTile(
                      dense: true,
                      leading: Icon(isCurrent ? Icons.check : Icons.call_split, size: 16),
                      title: Text(b),
                      selected: isCurrent,
                      onTap: isCurrent ? null : () => _switchBranch(b),
                    );
                  }).toList(),
                ),
              ),
            ),
            const Divider(),
            if (_creating) ...[
              TextField(
                controller: _newBranchCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome da nova branch',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
                onSubmitted: (_) => _createBranch(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(onPressed: () => setState(() => _creating = false), child: const Text('Cancelar')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _createBranch, child: const Text('Criar')),
                ],
              ),
            ] else
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Nova branch'),
                onPressed: () => setState(() => _creating = true),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
      ],
    );
  }
}
