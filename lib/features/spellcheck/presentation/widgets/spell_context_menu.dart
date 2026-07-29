import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import '../../domain/models/misspelling.dart';
import '../spellcheck_highlighter.dart';

/// Menu do botão direito com as correções da palavra clicada.
///
/// Substitui o menu embutido da biblioteca (que só tem cortar/copiar/colar,
/// e em inglês). Quando o clique cai sobre uma palavra desconhecida, as
/// sugestões vêm primeiro, seguidas de ignorar e aprender.
ContextMenuWidgetBuilder buildSpellcheckContextMenuBuilder({
  required SpellcheckHighlighter highlighter,
}) {
  return (context, position, editorState, onPressed) => _SpellContextMenu(
        position: position,
        editorState: editorState,
        onPressed: onPressed,
        highlighter: highlighter,
      );
}

class _MisspelledTarget {
  final Node node;
  final Misspelling misspelling;
  const _MisspelledTarget(this.node, this.misspelling);
}

class _SpellContextMenu extends StatelessWidget {
  final Offset position;
  final EditorState editorState;
  final VoidCallback onPressed;
  final SpellcheckHighlighter highlighter;

  const _SpellContextMenu({
    required this.position,
    required this.editorState,
    required this.onPressed,
    required this.highlighter,
  });

  /// A palavra sob o clique: o AppFlowy já move o cursor para lá antes de
  /// abrir o menu, então basta olhar a seleção.
  _MisspelledTarget? get _target {
    if (!highlighter.isEnabled) return null;
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) return null;
    final node = editorState.getNodeAtPath(selection.start.path);
    if (node == null || node.delta == null) return null;
    final misspelling = highlighter.at(node, selection.start.offset);
    if (misspelling == null) return null;
    return _MisspelledTarget(node, misspelling);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = _target;
    final checker = highlighter.checker;

    final items = <Widget>[];

    if (target != null && checker != null) {
      final suggestions = checker.suggest(target.misspelling.word, limit: 5);
      if (suggestions.isEmpty) {
        items.add(const _MenuLabel('Nenhuma sugestão'));
      } else {
        items.addAll(
          suggestions.map(
            (suggestion) => _MenuItem(
              label: suggestion,
              emphasized: true,
              onTap: () => _replace(target, suggestion),
            ),
          ),
        );
      }
      items.add(const _MenuDivider());
      items.add(
        _MenuItem(
          label: 'Ignorar nesta sessão',
          onTap: () {
            checker.ignore(target.misspelling.word);
            highlighter.invalidate();
            onPressed();
          },
        ),
      );
      items.add(
        _MenuItem(
          label: 'Adicionar ao dicionário do projeto',
          onTap: () async {
            await checker.learn(target.misspelling.word);
            highlighter.invalidate();
            onPressed();
          },
        ),
      );
      items.add(const _MenuDivider());
    }

    items.addAll([
      _MenuItem(label: 'Cortar', onTap: () => _run(handleCut)),
      _MenuItem(label: 'Copiar', onTap: () => _run(handleCopy)),
      _MenuItem(label: 'Colar', onTap: () => _run(handlePaste)),
    ]);

    return Positioned(
      top: position.dy,
      left: position.dx,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(6),
        color: theme.colorScheme.surfaceContainerHighest,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: items,
            ),
          ),
        ),
      ),
    );
  }

  void _run(void Function(EditorState) action) {
    action(editorState);
    onPressed();
  }

  Future<void> _replace(_MisspelledTarget target, String suggestion) async {
    final transaction = editorState.transaction
      ..replaceText(
        target.node,
        target.misspelling.start,
        target.misspelling.length,
        suggestion,
      );
    await editorState.apply(transaction);
    onPressed();
  }
}

class _MenuItem extends StatelessWidget {
  final String label;
  final bool emphasized;
  final VoidCallback onTap;

  const _MenuItem({
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: emphasized ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  final String text;
  const _MenuLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.disabledColor,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, indent: 8, endIndent: 8);
}
