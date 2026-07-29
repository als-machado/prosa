import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'spellcheck_highlighter.dart';

/// Monta o decorador que desenha o sublinhado ondulado nas palavras
/// desconhecidas.
///
/// O AppFlowy chama este decorador para cada trecho (`TextInsert`) do delta
/// do parágrafo, passando em `index` o deslocamento do trecho dentro do nó.
/// Devolvemos o mesmo trecho quebrado em pedaços, com estilo diferente nas
/// palavras erradas. O texto somado dos pedaços é idêntico ao original — é o
/// que mantém o cursor, a seleção e a busca funcionando: para o editor, nada
/// mudou.
///
/// Encadeie sobre o decorador que já estiver em uso (por padrão o da própria
/// biblioteca, que trata links) passando [base].
TextSpanDecoratorForAttribute buildSpellcheckTextSpanDecorator({
  required SpellcheckHighlighter highlighter,
  required Color color,
  TextSpanDecoratorForAttribute? base,
}) {
  final chained = base ?? defaultTextSpanDecoratorForAttribute;

  return (context, node, index, textInsert, before, after) {
    final decorated = chained(context, node, index, textInsert, before, after);
    if (!highlighter.isEnabled) return decorated;

    // Só o caso simples é reescrito: se o decorador anterior já devolveu algo
    // composto (link com gesto, menção, comentário), mexer ali quebraria o
    // comportamento dele.
    if (decorated is! TextSpan) return decorated;
    final text = decorated.text;
    if (text == null || text.isEmpty || decorated.children != null) {
      return decorated;
    }

    // Código e URL não passam por corretor em nenhum editor decente.
    final attributes = textInsert.attributes;
    if (attributes != null && (attributes.code || attributes.href != null)) {
      return decorated;
    }

    final misspellings = highlighter.visibleFor(node);
    if (misspellings.isEmpty) return decorated;

    final insertEnd = index + text.length;
    final baseStyle = decorated.style;
    final markedStyle = (baseStyle ?? const TextStyle()).copyWith(
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.wavy,
      decorationColor: color,
      decorationThickness: 1.2,
    );

    final children = <InlineSpan>[];
    var cursor = 0;

    for (final misspelling in misspellings) {
      if (misspelling.end <= index) continue;
      if (misspelling.start >= insertEnd) break;

      final from = (misspelling.start - index).clamp(0, text.length);
      final to = (misspelling.end - index).clamp(0, text.length);
      if (to <= cursor) continue;

      if (from > cursor) {
        children.add(TextSpan(text: text.substring(cursor, from), style: baseStyle));
      }
      children.add(TextSpan(text: text.substring(from, to), style: markedStyle));
      cursor = to;
    }

    if (children.isEmpty) return decorated;
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor), style: baseStyle));
    }

    return TextSpan(style: baseStyle, children: children);
  };
}
