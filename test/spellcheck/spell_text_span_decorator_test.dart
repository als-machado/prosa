import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosa/core/theme/app_theme.dart';
import 'package:prosa/features/spellcheck/data/bloom_dictionary.dart';
import 'package:prosa/features/spellcheck/data/plausibility_model.dart';
import 'package:prosa/features/spellcheck/data/spell_checker.dart';
import 'package:prosa/features/spellcheck/data/user_dictionary.dart';
import 'package:prosa/features/spellcheck/domain/models/spell_language.dart';
import 'package:prosa/features/spellcheck/presentation/spell_text_span_decorator.dart';
import 'package:prosa/features/spellcheck/presentation/spellcheck_highlighter.dart';

BloomDictionary _bloom(String name) =>
    BloomDictionary.fromBytes(File('assets/dictionaries/$name.bloom').readAsBytesSync());

SpellChecker _checker() => SpellChecker(
      dictionary: _bloom('pt_BR'),
      language: SpellLanguage.ptBR,
      userDictionary: UserDictionary(),
      plausibility: PlausibilityModel(_bloom('pt_BR.ngram')),
    );

/// Roda o decorador sobre um parágrafo e devolve o span resultante.
Future<TextSpan> _decorate(
  WidgetTester tester,
  String paragraph, {
  Color color = const Color(0xFFFF5252),
}) async {
  final editorState = EditorState(document: markdownToDocument(paragraph));
  final node = editorState.document.root.children.first;

  final highlighter = SpellcheckHighlighter()..checker = _checker();
  addTearDown(highlighter.dispose);

  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  final context = tester.element(find.byType(SizedBox));

  final decorator = buildSpellcheckTextSpanDecorator(
    highlighter: highlighter,
    color: color,
  );
  final text = node.delta!.toPlainText();
  final plain = TextSpan(text: text, style: const TextStyle(fontSize: 16));
  final result = decorator(context, node, 0, TextInsert(text), plain, plain);
  return result as TextSpan;
}

String _flatten(TextSpan span) {
  final buffer = StringBuffer();
  span.visitChildren((child) {
    if (child is TextSpan) buffer.write(child.text ?? '');
    return true;
  });
  return buffer.toString();
}

List<TextSpan> _marked(TextSpan span) {
  final marked = <TextSpan>[];
  span.visitChildren((child) {
    if (child is TextSpan && child.style?.decorationStyle == TextDecorationStyle.wavy) {
      marked.add(child);
    }
    return true;
  });
  return marked;
}

void main() {
  testWidgets('sublinha só a palavra errada, com onda na cor pedida',
      (tester) async {
    final span = await _decorate(tester, 'Ela abriu a porta e sussurou algo.');
    final marked = _marked(span);

    expect(marked.map((s) => s.text), ['sussurou']);
    expect(marked.single.style?.decoration, TextDecoration.underline);
    expect(marked.single.style?.decorationColor, const Color(0xFFFF5252));
  });

  testWidgets('o texto sai idêntico ao que entrou', (tester) async {
    // Esta é a invariante que mantém cursor, seleção e busca funcionando: o
    // decorador quebra o trecho em pedaços, mas a soma dos pedaços é o mesmo
    // texto, com o mesmo comprimento.
    const paragraph = 'Ela abriu a porta e sussurou algo, com chapeu na mão.';
    final span = await _decorate(tester, paragraph);
    expect(_flatten(span), paragraph);
    expect(_flatten(span).length, paragraph.length);
  });

  testWidgets('parágrafo correto não vira span nenhum', (tester) async {
    final span = await _decorate(tester, 'Ela abriu a porta do quarto.');
    expect(_marked(span), isEmpty);
  });

  testWidgets('preserva o estilo do texto por baixo da marcação',
      (tester) async {
    final span = await _decorate(tester, 'Ela sussurou algo.');
    // A marcação só acrescenta decoração; o resto do estilo continua.
    expect(_marked(span).single.style?.fontSize, 16);
  });

  test('a cor do sublinhado muda entre os temas', () {
    final claro = AppTheme.spellcheckUnderline(Brightness.light);
    final escuro = AppTheme.spellcheckUnderline(Brightness.dark);
    expect(claro, isNot(escuro));
    // No tema escuro tem de ser um vermelho saturado: o error do Material 3
    // (#FFB4AB) é claro, mas lavado, e desaparecia no meio do texto.
    expect(escuro, const Color(0xFFFF5252));
  });
}
