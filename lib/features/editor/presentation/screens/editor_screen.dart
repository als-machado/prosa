import 'dart:async';
import 'dart:ui' show AppExitResponse;
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
import '../../../../features/projects/presentation/providers/project_tree_provider.dart';
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
  static const _autosaveDelay = Duration(seconds: 3);
  static const _minFontSize = 10.0;
  static const _maxFontSize = 32.0;
  static const _defaultFontSize = 16.0;

  EditorState? _editorState;
  StreamSubscription? _transactionSub;
  Timer? _autosaveTimer;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onExitRequested: _onExitRequested);
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _lifecycleListener.dispose();
    _transactionSub?.cancel();
    _editorState?.dispose();
    super.dispose();
  }

  /// Fechar a janela com alterações pendentes salva antes de sair.
  Future<AppExitResponse> _onExitRequested() async {
    final path = ref.read(activeFileProvider);
    final state = _editorState;
    if (path != null && state != null && ref.read(editorNotifierProvider)) {
      await ref
          .read(editorNotifierProvider.notifier)
          .saveToFile(path, documentToMarkdown(state.document));
    }
    return AppExitResponse.exit;
  }

  void _loadIntoEditor(String content) {
    _autosaveTimer?.cancel();
    _transactionSub?.cancel();
    _editorState?.dispose();

    final newState = EditorState(document: markdownToDocument(content));
    _transactionSub = newState.transactionStream.listen((_) {
      ref.read(editorNotifierProvider.notifier).markDirty();
      _scheduleAutosave();
    });

    setState(() => _editorState = newState);
    ref.read(editorNotifierProvider.notifier).reset();
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_autosaveDelay, () {
      final path = ref.read(activeFileProvider);
      if (path != null && ref.read(editorNotifierProvider)) {
        _save(path, notify: false);
      }
    });
  }

  /// Ao trocar de arquivo, persiste as alterações pendentes do arquivo
  /// anterior antes que o novo conteúdo substitua o editor.
  void _flushPendingSave(String previousPath) {
    _autosaveTimer?.cancel();
    final state = _editorState;
    if (state == null || !ref.read(editorNotifierProvider)) return;
    final markdown = documentToMarkdown(state.document);
    unawaited(
      ref.read(editorNotifierProvider.notifier).saveToFile(previousPath, markdown),
    );
  }

  @override
  Widget build(BuildContext context) {
    final focusMode = ref.watch(focusModeProvider);
    final settings = ref.watch(settingsProvider).valueOrNull ?? const AppSettings();
    final activeFile = ref.watch(activeFileProvider);
    final isDirty = ref.watch(editorNotifierProvider);

    ref.listen(activeFileProvider, (prev, next) {
      if (prev != null && prev != next) _flushPendingSave(prev);
    });
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
                    isDirty: isDirty,
                    onSave: activeFile != null ? () => _save(activeFile) : null,
                    onCommit: () => _showCommitDialog(),
                    onPush: () => _push(),
                    onPull: () => _pull(),
                    onToggleFocus: () => ref.read(focusModeProvider.notifier).state = true,
                    editorState: _editorState,
                    fontSize: settings.editorFontSize,
                    onIncreaseFontSize: settings.editorFontSize < _maxFontSize ? _increaseFontSize : null,
                    onDecreaseFontSize: settings.editorFontSize > _minFontSize ? _decreaseFontSize : null,
                    onResetFontSize: _resetFontSize,
                  ),
                Expanded(
                  child: activeFile == null
                      ? const Center(child: Text('Selecione um arquivo no menu lateral'))
                      : _buildEditor(settings, activeFile),
                ),
                if (focusMode)
                  _FocusBar(
                    isDirty: isDirty,
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
          CommandShortcutEvent(
            key: 'increase-font-size',
            getDescription: () => 'Aumentar tamanho do texto',
            command: 'ctrl+equal',
            handler: (_) {
              _increaseFontSize();
              return KeyEventResult.handled;
            },
          ),
          CommandShortcutEvent(
            key: 'decrease-font-size',
            getDescription: () => 'Diminuir tamanho do texto',
            command: 'ctrl+minus',
            handler: (_) {
              _decreaseFontSize();
              return KeyEventResult.handled;
            },
          ),
          CommandShortcutEvent(
            key: 'reset-font-size',
            getDescription: () => 'Restaurar tamanho padrão do texto',
            command: 'ctrl+digit 0',
            handler: (_) {
              _resetFontSize();
              return KeyEventResult.handled;
            },
          ),
        ],
        editorStyle: EditorStyle.desktop(
          // Sem maxWidth: a biblioteca centraliza um bloco de largura fixa
          // dentro da janela quando maxWidth é definido, criando um espaço
          // vazio nas laterais que se soma ao padding e não encolhe com ele.
          // Deixando null, o padding abaixo é a única margem — a coluna de
          // texto ocupa toda a largura disponível menos essa margem.
          padding: EdgeInsets.symmetric(horizontal: settings.editorMarginHorizontal),
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

  Future<void> _save(String path, {bool notify = true}) async {
    final state = _editorState;
    if (state == null) return;
    _autosaveTimer?.cancel();
    final markdown = documentToMarkdown(state.document);
    try {
      await ref.read(editorNotifierProvider.notifier).saveToFile(path, markdown);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
      return;
    }
    if (notify && mounted) {
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
    try {
      await git.add(project.localPath);
      await git.commit(project.localPath, msg);
      ref.invalidate(commitLogProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Commit criado')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro no commit: $e')));
    }
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
      // O pull pode ter alterado a árvore e o arquivo aberto.
      ref.invalidate(projectTreeProvider);
      ref.invalidate(fileContentProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pull realizado')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro no pull: $e')));
    }
  }

  /// Tamanho do texto é uma preferência de exibição do editor inteiro, não
  /// formatação de um trecho — por isso vive em AppSettings (persistida e
  /// compartilhada entre arquivos), não no EditorState do documento aberto.
  Future<void> _changeFontSize(double Function(double current) transform) async {
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null) return;
    final next = transform(settings.editorFontSize).clamp(_minFontSize, _maxFontSize);
    await ref.read(settingsProvider.notifier).save(settings.copyWith(editorFontSize: next));
  }

  void _increaseFontSize() => _changeFontSize((s) => s + 1);
  void _decreaseFontSize() => _changeFontSize((s) => s - 1);
  void _resetFontSize() => _changeFontSize((_) => _defaultFontSize);

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
