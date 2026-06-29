import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/settings_provider.dart';
import '../../domain/models/app_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (s) => _SettingsBody(settings: s),
      ),
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  final AppSettings settings;
  const _SettingsBody({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _Section(title: 'Aparência', children: [
          SwitchListTile(
            title: const Text('Modo noturno'),
            secondary: const Icon(Icons.dark_mode_outlined),
            value: settings.darkMode,
            onChanged: (_) => ref.read(settingsProvider.notifier).toggleDarkMode(),
          ),
          ListTile(
            leading: const Icon(Icons.font_download_outlined),
            title: const Text('Fonte do editor'),
            subtitle: Text(settings.editorFont),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickFont(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.format_size),
            title: const Text('Tamanho da fonte'),
            subtitle: Text('${settings.editorFontSize.toInt()}pt'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickFontSize(context, ref),
          ),
        ]),
        const SizedBox(height: 24),
        _Section(title: 'Git', children: [
          ListTile(
            leading: const Icon(Icons.vpn_key_outlined),
            title: const Text('Configurar chave SSH'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/ssh'),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Servidor Git'),
            subtitle: Text(settings.gitProvider?.name ?? 'Não configurado'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickGitProvider(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.person_outlined),
            title: const Text('Usuário Git'),
            subtitle: Text(settings.gitUsername ?? 'Não configurado'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editUsername(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.token_outlined),
            title: const Text('Token de acesso'),
            subtitle: Text(
              settings.gitToken != null ? '••••••••${settings.gitToken!.length > 4 ? settings.gitToken!.substring(settings.gitToken!.length - 4) : ""}' : 'Não configurado',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editToken(context, ref),
          ),
        ]),
      ],
    );
  }

  Future<void> _pickFont(BuildContext context, WidgetRef ref) async {
    final fonts = ['Lora', 'Merriweather', 'Crimson Text', 'EB Garamond', 'Playfair Display', 'Source Serif 4', 'Roboto Mono'];
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Escolher fonte'),
        children: fonts.map((f) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, f),
          child: Text(f),
        )).toList(),
      ),
    );
    if (picked == null) return;
    await ref.read(settingsProvider.notifier).save(settings.copyWith(editorFont: picked));
  }

  Future<void> _pickFontSize(BuildContext context, WidgetRef ref) async {
    final sizes = [12.0, 14.0, 16.0, 18.0, 20.0, 24.0];
    final picked = await showDialog<double>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Tamanho da fonte'),
        children: sizes.map((s) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, s),
          child: Text('${s.toInt()}pt'),
        )).toList(),
      ),
    );
    if (picked == null) return;
    await ref.read(settingsProvider.notifier).save(settings.copyWith(editorFontSize: picked));
  }

  Future<void> _pickGitProvider(BuildContext context, WidgetRef ref) async {
    final providers = [GitProvider.github, GitProvider.gitlab];
    final picked = await showDialog<GitProvider>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Servidor Git'),
        children: [
          ...providers.map((p) => SimpleDialogOption(
            onPressed: () => Navigator.pop(context, p),
            child: Text(p.name),
          )),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Servidor personalizado...'),
          ),
        ],
      ),
    );
    if (picked != null) {
      await ref.read(settingsProvider.notifier).save(settings.copyWith(gitProvider: picked));
    }
  }

  Future<void> _editToken(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextInputDialog(
        title: 'Token de acesso Git',
        label: 'Personal Access Token',
        initialValue: settings.gitToken,
      ),
    );
    if (result == null) return;
    await ref.read(settingsProvider.notifier).save(settings.copyWith(gitToken: result));
  }

  Future<void> _editUsername(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextInputDialog(
        title: 'Usuário Git',
        label: 'Nome de usuário',
        initialValue: settings.gitUsername,
      ),
    );
    if (result == null) return;
    await ref.read(settingsProvider.notifier).save(settings.copyWith(gitUsername: result));
  }
}

class _TextInputDialog extends StatefulWidget {
  final String title;
  final String label;
  final String? initialValue;

  const _TextInputDialog({required this.title, required this.label, this.initialValue});

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _ctrl,
          decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder()),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text.trim()), child: const Text('Salvar')),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: Theme.of(context).colorScheme.primary)),
        ),
        Card(child: Column(children: children)),
      ],
    );
  }
}
