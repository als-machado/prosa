import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/git_provider.dart';

class SshSettingsScreen extends ConsumerWidget {
  const SshSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasKey = ref.watch(hasKeyPairProvider);
    final publicKey = ref.watch(publicKeyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Chave SSH')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Chave SSH', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('A chave SSH é usada para autenticar com o servidor Git sem senha.'),
              const SizedBox(height: 24),
              hasKey.when(
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('Erro: $e'),
                data: (has) => has
                    ? _KeyPresent(publicKey: publicKey.valueOrNull)
                    : _NoKey(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyPresent extends ConsumerWidget {
  final String? publicKey;
  const _KeyPresent({this.publicKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 20),
            const SizedBox(width: 8),
            const Text('Par de chaves SSH encontrado'),
          ],
        ),
        const SizedBox(height: 16),
        if (publicKey != null) ...[
          Text('Chave pública:', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(publicKey!, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copiar chave pública'),
                onPressed: () async {
                  final ssh = ref.read(sshServiceProvider);
                  await ssh.copyPublicKeyToClipboard();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Chave pública copiada!')),
                    );
                  }
                },
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Gerar novo par'),
                onPressed: () => _generate(context, ref),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _generate(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Gerar novo par de chaves'),
        content: const Text('Isso substituirá a chave existente. Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Gerar')),
        ],
      ),
    );
    if (confirmed != true) return;
    final ssh = ref.read(sshServiceProvider);
    await ssh.generateKeyPair();
    ref.invalidate(hasKeyPairProvider);
    ref.invalidate(publicKeyProvider);
  }
}

class _NoKey extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange, size: 20),
            SizedBox(width: 8),
            Text('Nenhuma chave SSH configurada'),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.vpn_key_outlined, size: 16),
          label: const Text('Gerar par de chaves SSH'),
          onPressed: () async {
            final ssh = ref.read(sshServiceProvider);
            await ssh.generateKeyPair();
            ref.invalidate(hasKeyPairProvider);
            ref.invalidate(publicKeyProvider);
          },
        ),
      ],
    );
  }
}
