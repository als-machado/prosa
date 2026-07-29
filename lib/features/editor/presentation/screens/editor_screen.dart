import 'dart:async';
import 'dart:ui' show AppExitResponse;
import 'package:appflowy_editor/appflowy_editor.dart';
// FindReplaceMenu não é exportado no barrel público do pacote — só é usado
// internamente por find_replace_command.dart. Precisamos da classe
// diretamente para guardar a referência e poder fechar o menu no Escape
// (a biblioteca não tem esse comportamento embutido).
// ignore: implementation_imports
import 'package:appflowy_editor/src/editor/find_replace_menu/find_menu_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/editor_provider.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/commit_dialog.dart';
import '../widgets/publish_dialog.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/code_block.dart';
import '../../domain/prosa_markdown.dart';
import '../../../../shared/widgets/sidebar/app_sidebar.dart';
import '../../../../features/git/presentation/providers/git_provider.dart';
import '../../../../features/projects/presentation/providers/projects_provider.dart';
import '../../../../features/projects/presentation/providers/project_tree_provider.dart';
import '../../../../features/settings/presentation/providers/settings_provider.dart';
import '../../../../features/settings/domain/models/app_settings.dart';
import '../../../../features/spellcheck/presentation/providers/spellcheck_provider.dart';
import '../../../../features/spellcheck/presentation/spell_text_span_decorator.dart';
import '../../../../features/spellcheck/presentation/spellcheck_highlighter.dart';
import '../../../../features/spellcheck/presentation/widgets/spell_context_menu.dart';

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

  // A biblioteca não tem lógica própria de Escape para o menu de
  // busca — ele mora num OverlayEntry separado do foco do editor, e o
  // atalho padrão de Escape só limpa a seleção de texto, sem saber que o
  // menu existe. Guardamos a referência para poder fechá-lo explicitamente.
  FindReplaceMenu? _findReplaceMenu;

  // Espelhos do estado do Riverpod, mantidos em campo porque `ref` NÃO pode
  // ser usado no dispose(): quando a janela fecha, o widget já está descartado
  // quando o dispose roda, e qualquer ref.read de lá estoura com
  // "Bad state: Cannot use ref after the widget was disposed" — o que
  // silenciosamente pulava justamente o salvamento de emergência abaixo.
  late final EditorNotifier _editorNotifier;
  SpellcheckHighlighter? _highlighter;
  String? _openFilePath;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    _editorNotifier = ref.read(editorNotifierProvider.notifier);
    _lifecycleListener = AppLifecycleListener(onExitRequested: _onExitRequested);
    HardwareKeyboard.instance.addHandler(_handleGlobalEscape);
  }

  @override
  void dispose() {
    // Sair da tela do editor (ex.: trocar de projeto) desmonta este widget
    // sem passar por _flushPendingSave nem _onExitRequested — sem isto,
    // alterações não salvas eram descartadas silenciosamente.
    _autosaveTimer?.cancel();
    final path = _openFilePath;
    if (path != null) _flushPendingSave(path);
    _findReplaceMenu?.dismiss();
    HardwareKeyboard.instance.removeHandler(_handleGlobalEscape);
    _lifecycleListener.dispose();
    _transactionSub?.cancel();
    _highlighter?.detach();
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
    _findReplaceMenu?.dismiss();
    _findReplaceMenu = null;
    final highlighter = ref.read(spellcheckHighlighterProvider);
    _highlighter = highlighter;
    // Antes do dispose: o destacador ouve o selectionNotifier do EditorState
    // que está sendo descartado.
    highlighter.detach();
    _editorState?.dispose();

    final newState = EditorState(document: markdownToEditorDocument(content));
    _transactionSub = newState.transactionStream.listen((_) {
      ref.read(editorNotifierProvider.notifier).markDirty();
      _scheduleAutosave();
    });

    // O destacador segue o documento aberto: guarda o resultado da
    // verificação por parágrafo e observa o cursor para não sublinhar a
    // palavra que está sendo digitada.
    highlighter.attach(newState);

    setState(() => _editorState = newState);
    ref.read(editorNotifierProvider.notifier).reset();
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_autosaveDelay, () {
      final path = _openFilePath;
      if (path != null && _isDirty) _save(path, notify: false);
    });
  }

  /// Ao trocar de arquivo, persiste as alterações pendentes do arquivo
  /// anterior antes que o novo conteúdo substitua o editor.
  void _flushPendingSave(String previousPath) {
    _autosaveTimer?.cancel();
    final state = _editorState;
    // Sem `ref` aqui: este método também roda do dispose().
    if (state == null || !_isDirty) return;
    final markdown = documentToMarkdown(state.document);
    unawaited(_editorNotifier.saveToFile(previousPath, markdown));
  }

  @override
  Widget build(BuildContext context) {
    final focusMode = ref.watch(focusModeProvider);
    final settings = ref.watch(settingsProvider).valueOrNull ?? const AppSettings();
    final activeFile = ref.watch(activeFileProvider);
    final isDirty = ref.watch(editorNotifierProvider);

    // Espelha para o dispose(), que não pode tocar em `ref`.
    _openFilePath = activeFile;
    _isDirty = isDirty;
    _highlighter = ref.watch(spellcheckHighlighterProvider);

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

  /// Sem textStyleBuilder, o HeadingBlockComponentBuilder usa tamanhos fixos
  /// (32/28/24/18pt) para os títulos, desconectados do tamanho de texto
  /// escolhido pelo usuário. Escala esses mesmos tamanhos-base na mesma
  /// proporção do corpo do texto, preservando a hierarquia visual entre
  /// título, subtítulo e parágrafo.
  TextStyle _headingTextStyle(int level, double bodyFontSize) {
    const defaultBodyFontSize = 16.0;
    const baseSizes = [32.0, 28.0, 24.0, 18.0, 18.0, 18.0];
    final base = level >= 0 && level < baseSizes.length ? baseSizes[level] : 18.0;
    final scale = bodyFontSize / defaultBodyFontSize;
    return TextStyle(fontSize: base * scale, fontWeight: FontWeight.bold);
  }

  Widget _buildEditor(AppSettings settings, String activeFile) {
    final editorState = _editorState;
    if (editorState == null) return const SizedBox.shrink();

    final baseStyle = _editorTextStyle(settings);
    final colorScheme = Theme.of(context).colorScheme;
    // build() já preencheu o campo antes de chegar aqui.
    final highlighter = _highlighter!;

    final prosaBlockConfig = BlockComponentConfiguration(
      padding: (_) => EdgeInsets.zero,
      placeholderText: (_) => '',
    );

    final blockComponentBuilders = {
      ...standardBlockComponentBuilderMap,
      ParagraphBlockKeys.type: ParagraphBlockComponentBuilder(
        configuration: prosaBlockConfig,
      ),
      HeadingBlockKeys.type: HeadingBlockComponentBuilder(
        configuration: prosaBlockConfig,
        textStyleBuilder: (level) => _headingTextStyle(level, settings.editorFontSize),
      ),
      // A biblioteca não traz componente para bloco de código; sem isto, o nó
      // não desenha.
      CodeBlockKeys.type: codeBlockComponentBuilder(
        fontSize: settings.editorFontSize,
        textColor: colorScheme.onSurface,
      ),
    };
    // AppFlowyEditor só reaplica blockComponentBuilders a editorState.renderer
    // quando editorState.service muda (troca de arquivo) — não a cada rebuild
    // do widget. Sem isto, o tamanho do título ficava "congelado" no valor de
    // quando o arquivo foi aberto, ignorando mudanças de editorFontSize.
    editorState.renderer = BlockComponentRenderer(builders: blockComponentBuilders);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: AppFlowyEditor(
        editorState: editorState,
        header: const SizedBox(height: 32),
        footer: const SizedBox(height: 32),
        blockComponentBuilders: blockComponentBuilders,
        contextMenuBuilder: buildSpellcheckContextMenuBuilder(
          highlighter: highlighter,
        ),
        characterShortcutEvents: [
          // Antes dos padrões: dentro do bloco de código, Enter quebra linha em
          // vez de criar bloco novo, e a formatação automática fica desligada.
          newLineInCodeBlock,
          codeBlockFromBackticks,
          ...withoutFormattingInsideCodeBlock(standardCharacterShortcutEvents),
        ],
        commandShortcutEvents: [
          ...standardCommandShortcutEvents.where((e) => e.key != 'indent'),
          _buildTabInsertCommand(settings.editorTabSize),
          CommandShortcutEvent(
            key: 'show the find dialog',
            getDescription: () => 'Buscar no arquivo',
            command: 'ctrl+f',
            macOSCommand: 'cmd+f',
            handler: (editorState) => _openFindReplace(editorState),
          ),
          CommandShortcutEvent(
            key: 'show the find and replace dialog',
            getDescription: () => 'Buscar e substituir no arquivo',
            command: 'ctrl+h',
            macOSCommand: 'cmd+h',
            handler: (editorState) => _openFindReplace(editorState, showReplace: true),
          ),
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
          // Sublinhado ondulado nas palavras desconhecidas. Encadeia sobre o
          // decorador padrão da biblioteca para não perder o tratamento de
          // links.
          textSpanDecorator: buildSpellcheckTextSpanDecorator(
            highlighter: highlighter,
            color: AppTheme.spellcheckUnderline(Theme.of(context).brightness),
          ),
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
      await _editorNotifier.saveToFile(path, markdown);
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

  KeyEventResult _openFindReplace(EditorState editorState, {bool showReplace = false}) {
    _findReplaceMenu?.dismiss();
    final menu = FindReplaceMenu(
      context: context,
      editorState: editorState,
      showReplaceMenu: showReplace,
      style: FindReplaceStyle(),
      localizations: FindReplaceLocalizations(
        find: 'Buscar',
        previousMatch: 'Anterior',
        nextMatch: 'Próximo',
        close: 'Fechar',
        replace: 'Substituir',
        replaceAll: 'Substituir tudo',
        noResult: 'Nenhum resultado',
      ),
      showRegexButton: true,
      showCaseSensitiveButton: true,
    );
    menu.show();
    _findReplaceMenu = menu;
    return KeyEventResult.handled;
  }

  /// Notificado a cada tecla física, independente de qual widget está com
  /// foco — necessário porque o campo de busca (num Overlay separado)
  /// captura o foco e tem seu próprio tratamento interno de Escape
  /// (DismissIntent do TextField, usado para esconder a barra de seleção),
  /// que intercepta o Escape antes que ele chegasse ao commandShortcutEvents
  /// do editor.
  bool _handleGlobalEscape(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _findReplaceMenu != null) {
      final menu = _findReplaceMenu!;
      _findReplaceMenu = null;
      // O despacho desta mesma tecla ainda está em andamento (o próprio
      // TextField do campo de busca também a processa, via seu
      // DismissIntent interno). Remover o overlay agora, de forma síncrona,
      // derrubaria a árvore de widgets no meio desse despacho. Uma
      // microtask roda só depois que o despacho atual termina.
      scheduleMicrotask(menu.dismiss);
      return true;
    }
    return false;
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
