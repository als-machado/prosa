import 'dart:async';
import 'package:appflowy_editor/appflowy_editor.dart';
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

CommandShortcutEvent _buildTabInsertCommand(int tabSize) {
  final indent = ' ' * tabSize;
  return CommandShortcutEvent(
    key: 'insert-tab',
    getDescription: () => 'Inserir indentação',
    command: 'tab',
    handler: (editorState) {
      final selection = editorState.selection;
      if (selection == null) return KeyEventResult.ignored;
      final node = editorState.getNodeAtPath(selection.start.path);
      if (node == null || node.delta == null) return KeyEventResult.ignored;
      final transaction = editorState.transaction
        ..insertText(node, selection.start.offset, indent);
      editorState.apply(transaction);
      return KeyEventResult.handled;
    },
  );
}

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  EditorState? _editorState;
  StreamSubscription? _transactionSub;

  @override
  void dispose() {
    _transactionSub?.cancel();
    _editorState?.dispose();
    super.dispose();
  }

  void _loadIntoEditor(String content) {
    _transactionSub?.cancel();
    _editorState?.dispose();

    final newState = EditorState(document: markdownToDocument(content));
    _transactionSub = newState.transactionStream.listen((_) {
      final markdown = documentToMarkdown(newState.document);
      ref.read(editorNotifierProvider.notifier).updateContent(markdown);
    });

    setState(() => _editorState = newState);
    ref.read(editorNotifierProvider.notifier).loadContent(content);
  }

  @override
  Widget build(BuildContext context) {
    final focusMode = ref.watch(focusModeProvider);
    final settings = ref.watch(settingsProvider).valueOrNull ?? const AppSettings();
    final activeFile = ref.watch(activeFileProvider);
    final editorDocState = ref.watch(editorNotifierProvider);

    ref.listen(fileContentProvider, (_, next) {
      next.whenData((content) => _loadIntoEditor(content));
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
                    isDirty: editorDocState.isDirty,
                    onSave: activeFile != null ? () => _save(activeFile) : null,
                    onCommit: () => _showCommitDialog(),
                    onPush: () => _push(),
                    onPull: () => _pull(),
                    onToggleFocus: () => ref.read(focusModeProvider.notifier).state = true,
                    editorState: _editorState,
                  ),
                Expanded(
                  child: activeFile == null
                      ? const Center(child: Text('Selecione um arquivo no menu lateral'))
                      : _buildEditor(settings, activeFile),
                ),
                if (focusMode)
                  _FocusBar(
                    isDirty: editorDocState.isDirty,
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
    final color = Theme.of(context).colorScheme.onSurface;
    try {
      return GoogleFonts.getFont(settings.editorFont, fontSize: settings.editorFontSize, height: 1.8, color: color);
    } catch (_) {
      return GoogleFonts.lora(fontSize: settings.editorFontSize, height: 1.8, color: color);
    }
  }

  Widget _buildEditor(AppSettings settings, String activeFile) {
    final editorState = _editorState;
    if (editorState == null) return const SizedBox.shrink();

    final baseStyle = _editorTextStyle(settings);
    final colorScheme = Theme.of(context).colorScheme;

    final prosaBlockConfig = BlockComponentConfiguration(
      padding: (_) => EdgeInsets.zero,
      placeholderText: (_) => '',
    );

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: AppFlowyEditor(
        editorState: editorState,
        header: const SizedBox(height: 32),
        footer: const SizedBox(height: 32),
        blockComponentBuilders: {
          ...standardBlockComponentBuilderMap,
          ParagraphBlockKeys.type: ParagraphBlockComponentBuilder(
            configuration: prosaBlockConfig,
          ),
          HeadingBlockKeys.type: HeadingBlockComponentBuilder(
            configuration: prosaBlockConfig,
          ),
        },
        commandShortcutEvents: [
          ...standardCommandShortcutEvents.where((e) => e.key != 'indent'),
          _buildTabInsertCommand(settings.editorTabSize),
          CommandShortcutEvent(
            key: 'save-file',
            getDescription: () => 'Salvar arquivo',
            command: 'ctrl+s',
            handler: (_) {
              _save(activeFile);
              return KeyEventResult.handled;
            },
          ),
        ],
        editorStyle: EditorStyle.desktop(
          padding: const EdgeInsets.symmetric(horizontal: 80),
          maxWidth: 720,
          cursorColor: colorScheme.primary,
          selectionColor: colorScheme.primary.withValues(alpha: 0.2),
          textStyleConfiguration: TextStyleConfiguration(
            text: baseStyle,
            bold: baseStyle.copyWith(fontWeight: FontWeight.bold),
            italic: baseStyle.copyWith(fontStyle: FontStyle.italic),
            strikethrough: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
            underline: baseStyle.copyWith(decoration: TextDecoration.underline),
            code: baseStyle.copyWith(fontFamily: 'monospace', fontSize: (settings.editorFontSize - 2).clamp(10, 72)),
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
