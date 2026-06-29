import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/editor_provider.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/commit_dialog.dart';
import '../widgets/publish_dialog.dart';
import '../../../../shared/widgets/sidebar/app_sidebar.dart';
import '../../../../features/git/presentation/providers/git_provider.dart';
import '../../../../features/projects/presentation/providers/projects_provider.dart';
import '../../../../features/settings/presentation/providers/settings_provider.dart';
import '../../../../features/settings/domain/models/app_settings.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focusMode = ref.watch(focusModeProvider);
    final settings = ref.watch(settingsProvider).valueOrNull ?? const AppSettings();
    final activeFile = ref.watch(activeFileProvider);
    final editorState = ref.watch(editorNotifierProvider);

    ref.listen(fileContentProvider, (_, next) {
      next.whenData((content) {
        ref.read(editorNotifierProvider.notifier).loadContent(content);
        _ctrl.text = content;
        _ctrl.selection = TextSelection.collapsed(offset: content.length);
      });
    });

    return Scaffold(
      body: Row(
        children: [
          if (!focusMode) const AppSidebar(),
          Expanded(
            child: Column(
              children: [
                if (!focusMode)
                  EditorToolbar(
                    isDirty: editorState.isDirty,
                    onSave: activeFile != null ? () => _save(activeFile) : null,
                    onCommit: () => _showCommitDialog(),
                    onPush: () => _push(),
                    onPull: () => _pull(),
                    onToggleFocus: () => ref.read(focusModeProvider.notifier).state = true,
                    controller: _ctrl,
                  ),
                Expanded(
                  child: activeFile == null
                      ? const Center(child: Text('Selecione um arquivo no menu lateral'))
                      : _buildEditor(settings),
                ),
                if (focusMode)
                  _FocusBar(
                    isDirty: editorState.isDirty,
                    onSave: activeFile != null ? () => _save(activeFile) : null,
                    onExit: () => ref.read(focusModeProvider.notifier).state = false,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _editorTextStyle(AppSettings settings) {
    try {
      return GoogleFonts.getFont(
        settings.editorFont,
        fontSize: settings.editorFontSize,
        height: 1.8,
      );
    } catch (_) {
      return GoogleFonts.lora(fontSize: settings.editorFontSize, height: 1.8);
    }
  }

  Widget _buildEditor(AppSettings settings) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: TextField(
              controller: _ctrl,
              maxLines: null,
              expands: true,
              decoration: const InputDecoration(border: InputBorder.none, hintText: 'Comece a escrever...'),
              style: _editorTextStyle(settings),
              onChanged: (v) => ref.read(editorNotifierProvider.notifier).updateContent(v),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save(String path) async {
    await ref.read(editorNotifierProvider.notifier).saveToFile(path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Salvo'), duration: Duration(seconds: 1)));
    }
  }

  Future<void> _showCommitDialog() async {
    final project = ref.read(activeProjectProvider);
    if (project == null) return;
    final msg = await showDialog<String>(
      context: context,
      builder: (_) => const CommitDialog(),
    );
    if (msg == null || msg.isEmpty) return;
    final git = ref.read(gitServiceProvider);
    await git.add(project.localPath);
    await git.commit(project.localPath, msg);
    ref.invalidate(commitLogProvider);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Commit criado')));
  }

  Future<void> _push() async {
    final project = ref.read(activeProjectProvider);
    if (project == null) return;
    final hasRemote = await ref.read(hasRemoteProvider.future);
    if (!hasRemote) {
      if (mounted) _showPublishDialog();
      return;
    }
    final sshKeyPath = await ref.read(sshKeyPathProvider.future);
    final branch = await ref.read(currentBranchProvider.future);
    try {
      final git = ref.read(gitServiceProvider);
      await git.push(project.localPath, sshKeyPath: sshKeyPath, branch: branch, setUpstream: true);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Push realizado')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro no push: $e')));
    }
  }

  Future<void> _pull() async {
    final project = ref.read(activeProjectProvider);
    if (project == null) return;
    final sshKeyPath = await ref.read(sshKeyPathProvider.future);
    final git = ref.read(gitServiceProvider);
    try {
      await git.pull(project.localPath, sshKeyPath: sshKeyPath);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pull realizado')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro no pull: $e')));
    }
  }

  Future<void> _showPublishDialog() async {
    final project = ref.read(activeProjectProvider);
    if (project == null) return;
    await showDialog(
      context: context,
      builder: (_) => PublishDialog(project: project),
    );
    ref.invalidate(hasRemoteProvider);
  }
}

class _FocusBar extends StatelessWidget {
  final bool isDirty;
  final VoidCallback? onSave;
  final VoidCallback onExit;
  const _FocusBar({required this.isDirty, this.onSave, required this.onExit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (isDirty && onSave != null)
            TextButton.icon(icon: const Icon(Icons.save_outlined, size: 16), label: const Text('Salvar'), onPressed: onSave),
          IconButton(icon: const Icon(Icons.fullscreen_exit, size: 18), tooltip: 'Sair do modo foco', onPressed: onExit),
        ],
      ),
    );
  }
}
