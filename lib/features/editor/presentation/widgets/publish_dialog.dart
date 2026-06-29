import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/prosa_project.dart';
import '../../../git/presentation/providers/git_provider.dart';
import '../../../git/presentation/providers/git_api_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

class PublishDialog extends ConsumerStatefulWidget {
  final ProsaProject project;
  const PublishDialog({super.key, required this.project});

  @override
  ConsumerState<PublishDialog> createState() => _PublishDialogState();
}

class _PublishDialogState extends ConsumerState<PublishDialog> {
  late final TextEditingController _nameCtrl;
  bool _private = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final slug = widget.project.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    _nameCtrl = TextEditingController(text: slug);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final settings = ref.read(settingsProvider).valueOrNull;
    final token = settings?.gitToken;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Configure o token Git em Configurações antes de publicar.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final api = ref.read(gitApiServiceProvider);
      final repo = await api.createGithubRepo(
        token,
        _nameCtrl.text.trim(),
        description: widget.project.title,
        private: _private,
      );
      if (repo == null) throw Exception('Falha ao criar repositório');

      final git = ref.read(gitServiceProvider);
      final sshKeyPath = await ref.read(sshKeyPathProvider.future);
      final branch = await ref.read(currentBranchProvider.future) ?? 'main';

      await git.addRemote(widget.project.localPath, repo.sshUrl);
      await git.push(
        widget.project.localPath,
        sshKeyPath: sshKeyPath,
        branch: branch,
        setUpstream: true,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Publicado em ${repo.sshUrl}')),
        );
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final hasToken = settings?.gitToken?.isNotEmpty == true;

    return AlertDialog(
      title: const Text('Publicar no GitHub'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!hasToken) ...[
              const Icon(Icons.warning_amber, color: Colors.orange),
              const SizedBox(height: 8),
              const Text('Token de acesso Git não configurado. Vá em Configurações → Token de Acesso.'),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome do repositório',
                border: OutlineInputBorder(),
              ),
              enabled: !_loading,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Repositório privado'),
              value: _private,
              onChanged: _loading ? null : (v) => setState(() => _private = v),
              contentPadding: EdgeInsets.zero,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: (_loading || !hasToken) ? null : _publish,
          child: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Publicar'),
        ),
      ],
    );
  }
}
