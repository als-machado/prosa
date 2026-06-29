import 'package:flutter/widgets.dart';

class MarkdownFormatter {
  static void wrap(TextEditingController ctrl, String prefix, [String? suffix]) {
    suffix ??= prefix;
    final text = ctrl.text;
    final sel = ctrl.selection;
    if (!sel.isValid) return;

    final selected = sel.textInside(text);
    final replacement = '$prefix$selected$suffix';
    final newText = text.replaceRange(sel.start, sel.end, replacement);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: sel.start + replacement.length,
      ),
    );
  }

  static void bold(TextEditingController ctrl) => wrap(ctrl, '**');
  static void italic(TextEditingController ctrl) => wrap(ctrl, '_');
  static void strikethrough(TextEditingController ctrl) => wrap(ctrl, '~~');
  static void heading(TextEditingController ctrl, int level) {
    final prefix = '${'#' * level} ';
    final text = ctrl.text;
    final sel = ctrl.selection;
    if (!sel.isValid) return;
    final lineStart = text.lastIndexOf('\n', sel.start - 1) + 1;
    final newText = text.substring(0, lineStart) + prefix + text.substring(lineStart);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + prefix.length),
    );
  }
}
