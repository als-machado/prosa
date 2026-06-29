import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

class EditorToolbar extends StatelessWidget {
  final bool isDirty;
  final VoidCallback? onSave;
  final VoidCallback onCommit;
  final VoidCallback onPush;
  final VoidCallback onPull;
  final VoidCallback onToggleFocus;
  final EditorState? editorState;

  const EditorToolbar({
    super.key,
    required this.isDirty,
    this.onSave,
    required this.onCommit,
    required this.onPush,
    required this.onPull,
    required this.onToggleFocus,
    this.editorState,
  });

  void _toggleInline(String attribute) {
    final state = editorState;
    if (state == null) return;
    state.toggleAttribute(attribute);
  }

  void _applyHeading(int level) {
    final state = editorState;
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

  @override
  Widget build(BuildContext context) {
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
            onPressed: isDirty ? onSave : null,
            badge: isDirty,
          ),
          const _Separator(),
          _ToolbarButton(
            icon: Icons.format_bold,
            tooltip: 'Negrito (Ctrl+B)',
            onPressed: editorState != null ? () => _toggleInline(AppFlowyRichTextKeys.bold) : null,
          ),
          _ToolbarButton(
            icon: Icons.format_italic,
            tooltip: 'Itálico (Ctrl+I)',
            onPressed: editorState != null ? () => _toggleInline(AppFlowyRichTextKeys.italic) : null,
          ),
          _ToolbarButton(
            icon: Icons.format_strikethrough,
            tooltip: 'Tachado',
            onPressed: editorState != null ? () => _toggleInline(AppFlowyRichTextKeys.strikethrough) : null,
          ),
          const _Separator(),
          _ToolbarButton(
            icon: Icons.title,
            tooltip: 'Título H1',
            onPressed: editorState != null ? () => _applyHeading(1) : null,
          ),
          _ToolbarButton(
            icon: Icons.format_size,
            tooltip: 'Subtítulo H2',
            onPressed: editorState != null ? () => _applyHeading(2) : null,
          ),
          const _Separator(),
          _ToolbarButton(icon: Icons.commit, tooltip: 'Commit', onPressed: onCommit),
          _ToolbarButton(icon: Icons.cloud_upload_outlined, tooltip: 'Push', onPressed: onPush),
          _ToolbarButton(icon: Icons.cloud_download_outlined, tooltip: 'Pull', onPressed: onPull),
          const Spacer(),
          _ToolbarButton(
            icon: Icons.fullscreen,
            tooltip: 'Modo foco',
            onPressed: onToggleFocus,
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

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.badge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          IconButton(
            icon: Icon(icon, size: 18),
            onPressed: onPressed,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          if (badge)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
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
