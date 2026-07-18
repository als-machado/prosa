import 'dart:async';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

class EditorToolbar extends StatefulWidget {
  final bool isDirty;
  final VoidCallback? onSave;
  final VoidCallback onCommit;
  final VoidCallback onPush;
  final VoidCallback onPull;
  final VoidCallback onToggleFocus;
  final EditorState? editorState;
  final double fontSize;
  final VoidCallback? onIncreaseFontSize;
  final VoidCallback? onDecreaseFontSize;
  final VoidCallback? onResetFontSize;

  const EditorToolbar({
    super.key,
    required this.isDirty,
    this.onSave,
    required this.onCommit,
    required this.onPush,
    required this.onPull,
    required this.onToggleFocus,
    this.editorState,
    this.fontSize = 16.0,
    this.onIncreaseFontSize,
    this.onDecreaseFontSize,
    this.onResetFontSize,
  });

  @override
  State<EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends State<EditorToolbar> {
  StreamSubscription<EditorTransactionValue>? _transactionSub;

  @override
  void initState() {
    super.initState();
    _attachListeners();
  }

  @override
  void didUpdateWidget(covariant EditorToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editorState != widget.editorState) {
      _detachListeners(oldWidget.editorState);
      _attachListeners();
    }
  }

  @override
  void dispose() {
    _detachListeners(widget.editorState);
    super.dispose();
  }

  // O estado "ativo" de negrito/itálico depende da seleção atual e do
  // toggledStyle (estilo pendente com o cursor colapsado) — nenhum dos
  // dois é um Listenable único, então escutamos os três sinais que podem
  // mudar o resultado: seleção, toggledStyle e qualquer transação (o
  // conteúdo sob a mesma seleção pode mudar sem a seleção em si mudar).
  void _attachListeners() {
    final state = widget.editorState;
    if (state == null) return;
    state.selectionNotifier.addListener(_onEditorChanged);
    state.toggledStyleNotifier.addListener(_onEditorChanged);
    _transactionSub = state.transactionStream.listen((_) => _onEditorChanged());
  }

  void _detachListeners(EditorState? state) {
    state?.selectionNotifier.removeListener(_onEditorChanged);
    state?.toggledStyleNotifier.removeListener(_onEditorChanged);
    _transactionSub?.cancel();
    _transactionSub = null;
  }

  void _onEditorChanged() {
    if (mounted) setState(() {});
  }

  void _toggleInline(String attribute) {
    final state = widget.editorState;
    if (state == null) return;
    state.toggleAttribute(attribute);
  }

  bool _isAttributeActive(String key) {
    final state = widget.editorState;
    if (state == null) return false;
    final selection = state.selection;
    if (selection == null) return false;

    if (selection.isCollapsed) {
      if (state.toggledStyle.containsKey(key)) {
        return state.toggledStyle[key] == true;
      }
      final nodes = state.getNodesInSelection(selection);
      final lookBehind = selection.copyWith(
        start: selection.start.copyWith(
          offset: (selection.startIndex - 1).clamp(0, selection.startIndex),
        ),
      );
      return nodes.allSatisfyInSelection(
        lookBehind,
        (delta) => delta.everyAttributes((attr) => attr[key] == true),
      );
    }

    final nodes = state.getNodesInSelection(selection);
    return nodes.allSatisfyInSelection(
      selection,
      (delta) => delta.isNotEmpty && delta.everyAttributes((attr) => attr[key] == true),
    );
  }

  void _applyHeading(int level) {
    final state = widget.editorState;
    if (state == null) return;
    final selection = state.selection;
    if (selection == null) return;

    final node = state.getNodeAtPath(selection.start.path);
    if (node == null) return;

    final isAlreadyThisHeading =
        node.type == HeadingBlockKeys.type && node.attributes[HeadingBlockKeys.level] == level;

    state.formatNode(
      selection,
      (node) => node.copyWith(
        type: isAlreadyThisHeading ? ParagraphBlockKeys.type : HeadingBlockKeys.type,
        attributes: {
          HeadingBlockKeys.level: level,
          blockComponentDelta: (node.delta ?? Delta()).toJson(),
        },
      ),
    );
  }

  bool _isHeadingActive(int level) {
    final state = widget.editorState;
    if (state == null) return false;
    final selection = state.selection;
    if (selection == null) return false;
    final node = state.getNodeAtPath(selection.start.path);
    if (node == null) return false;
    return node.type == HeadingBlockKeys.type && node.attributes[HeadingBlockKeys.level] == level;
  }

  @override
  Widget build(BuildContext context) {
    final editorState = widget.editorState;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _ToolbarButton(
            icon: Icons.save_outlined,
            tooltip: 'Salvar (Ctrl+S)',
            onPressed: widget.isDirty ? widget.onSave : null,
            badge: widget.isDirty,
          ),
          const _Separator(),
          _ToolbarButton(
            icon: Icons.format_bold,
            tooltip: 'Negrito (Ctrl+B)',
            onPressed: editorState != null ? () => _toggleInline(AppFlowyRichTextKeys.bold) : null,
            isActive: _isAttributeActive(AppFlowyRichTextKeys.bold),
          ),
          _ToolbarButton(
            icon: Icons.format_italic,
            tooltip: 'Itálico (Ctrl+I)',
            onPressed: editorState != null ? () => _toggleInline(AppFlowyRichTextKeys.italic) : null,
            isActive: _isAttributeActive(AppFlowyRichTextKeys.italic),
          ),
          _ToolbarButton(
            icon: Icons.format_strikethrough,
            tooltip: 'Tachado',
            onPressed: editorState != null ? () => _toggleInline(AppFlowyRichTextKeys.strikethrough) : null,
            isActive: _isAttributeActive(AppFlowyRichTextKeys.strikethrough),
          ),
          _ToolbarButton(
            icon: Icons.format_underlined,
            tooltip: 'Sublinhado (Ctrl+U)',
            onPressed: editorState != null ? () => _toggleInline(AppFlowyRichTextKeys.underline) : null,
            isActive: _isAttributeActive(AppFlowyRichTextKeys.underline),
          ),
          const _Separator(),
          _ToolbarButton(
            icon: Icons.title,
            tooltip: 'Título H1',
            onPressed: editorState != null ? () => _applyHeading(1) : null,
            isActive: _isHeadingActive(1),
          ),
          _ToolbarButton(
            icon: Icons.format_size,
            tooltip: 'Subtítulo H2',
            onPressed: editorState != null ? () => _applyHeading(2) : null,
            isActive: _isHeadingActive(2),
          ),
          const _Separator(),
          _ToolbarButton(icon: Icons.commit, tooltip: 'Commit', onPressed: widget.onCommit),
          _ToolbarButton(icon: Icons.cloud_upload_outlined, tooltip: 'Push', onPressed: widget.onPush),
          _ToolbarButton(icon: Icons.cloud_download_outlined, tooltip: 'Pull', onPressed: widget.onPull),
          const Spacer(),
          _FontSizeStepper(
            fontSize: widget.fontSize,
            onDecrease: widget.onDecreaseFontSize,
            onIncrease: widget.onIncreaseFontSize,
            onReset: widget.onResetFontSize,
          ),
          const _Separator(),
          _ToolbarButton(
            icon: Icons.fullscreen,
            tooltip: 'Modo foco',
            onPressed: widget.onToggleFocus,
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool badge;
  final bool isActive;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.badge = false,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          Container(
            decoration: BoxDecoration(
              color: isActive ? colorScheme.primary.withValues(alpha: 0.22) : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: IconButton(
              icon: Icon(icon, size: 18, color: isActive ? colorScheme.primary : null),
              onPressed: onPressed,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ),
          if (badge)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ajusta o tamanho do texto exibido no editor inteiro (não formatação de
/// um trecho) — pensado para adequar a tela ou compensar limitações de
/// visão sem precisar entrar em Configurações.
class _FontSizeStepper extends StatelessWidget {
  final double fontSize;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;
  final VoidCallback? onReset;

  const _FontSizeStepper({
    required this.fontSize,
    this.onDecrease,
    this.onIncrease,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Diminuir tamanho do texto (Ctrl+-)',
          child: IconButton(
            icon: const Icon(Icons.text_decrease, size: 18),
            onPressed: onDecrease,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ),
        Tooltip(
          message: 'Restaurar tamanho padrão',
          child: InkWell(
            onTap: onReset,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Text(
                '${fontSize.round()}pt',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
        Tooltip(
          message: 'Aumentar tamanho do texto (Ctrl+=)',
          child: IconButton(
            icon: const Icon(Icons.text_increase, size: 18),
            onPressed: onIncrease,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ),
      ],
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Theme.of(context).dividerColor,
    );
  }
}
