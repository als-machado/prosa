import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosa/features/editor/domain/code_block.dart';
import 'package:prosa/features/editor/domain/prosa_markdown.dart';

const _comCodigo = '''
# Notas de implementação
O trecho abaixo resolve o problema:
```dart
void main() {
  print("oi");
}
```
Depois do bloco, o texto continua.
''';

Node _nodeAt(Document document, int index) => document.root.children[index];

Future<EditorState> _pump(WidgetTester tester, Document document) async {
  final editorState = EditorState(document: document);
  final builders = {
    ...standardBlockComponentBuilderMap,
    CodeBlockKeys.type:
        codeBlockComponentBuilder(fontSize: 16, textColor: Colors.black),
  };
  editorState.renderer = BlockComponentRenderer(builders: builders);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 600,
          child: AppFlowyEditor(
            editorState: editorState,
            blockComponentBuilders: builders,
            characterShortcutEvents: [
              newLineInCodeBlock,
              codeBlockFromBackticks,
              ...withoutFormattingInsideCodeBlock(standardCharacterShortcutEvents),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return editorState;
}

/// Insere texto sem passar pelos atalhos, para montar o estado do caso.
Future<void> _digita(WidgetTester tester, EditorState editorState, String texto) async {
  await editorState.insertTextAtCurrentSelection(texto);
  await tester.pumpAndSettle();
}

/// Aciona um atalho de caractere como o editor faria ao receber a tecla.
///
/// O caminho real vem do IME, que não existe no teste; o que se testa aqui é a
/// decisão do atalho, que é o código deste projeto.
Future<bool> _aciona(
  WidgetTester tester,
  CharacterShortcutEvent event,
  EditorState editorState,
) async {
  final tratou = await event.handler(editorState);
  await tester.pumpAndSettle();
  return tratou;
}

void main() {
  group('leitura e escrita', () {
    test('bloco de código sobrevive ao abrir', () {
      final documento = markdownToEditorDocument(_comCodigo);
      final codigo = documento.root.children
          .where((n) => n.type == CodeBlockKeys.type)
          .toList();
      expect(codigo, hasLength(1), reason: 'o bloco não pode desaparecer');
      expect(codigo.single.delta!.toPlainText(),
          'void main() {\n  print("oi");\n}');
      expect(codigo.single.attributes[CodeBlockKeys.language], 'dart');
    });

    test('salvar depois de abrir devolve o mesmo arquivo', () {
      final documento = markdownToEditorDocument(_comCodigo);
      expect(documentToMarkdown(documento).trimRight(), _comCodigo.trimRight());
    });

    test('cerca sem fechamento não perde o conteúdo', () {
      const semFechar = '# T\n```\nlinha de código\n';
      final documento = markdownToEditorDocument(semFechar);
      final codigo =
          documento.root.children.where((n) => n.type == CodeBlockKeys.type);
      expect(codigo.single.delta!.toPlainText(), 'linha de código');
    });

    test('quebras dentro do bloco não viram nós separados', () {
      final documento = markdownToEditorDocument(_comCodigo);
      expect(
        documento.root.children.where((n) => n.type == CodeBlockKeys.type),
        hasLength(1),
      );
    });
  });

  group('linhas em branco', () {
    const comLinhasEmBranco = '''
# Resumo
capítulo 1:
Texto do primeiro capítulo.

capítulo 2:
Texto do segundo capítulo.


capítulo 3:
''';

    test('linha em branco digitada pelo autor é preservada', () {
      final documento = markdownToEditorDocument(comLinhasEmBranco);
      final textos = documento.root.children
          .map((n) => n.delta?.toPlainText() ?? '')
          .toList();
      expect(textos, [
        'Resumo',
        'capítulo 1:',
        'Texto do primeiro capítulo.',
        '',
        'capítulo 2:',
        'Texto do segundo capítulo.',
        '',
        '',
        'capítulo 3:',
      ]);
    });

    test('salvar e abrir de novo mantém as linhas em branco', () {
      // Era exatamente isto que se perdia: fechar o editor e abrir o arquivo
      // apagava os pulos de linha entre os resumos de capítulo.
      final primeiro = markdownToEditorDocument(comLinhasEmBranco);
      final salvo = documentToMarkdown(primeiro);
      expect(salvo.trimRight(), comLinhasEmBranco.trimRight());

      final segundo = markdownToEditorDocument(salvo);
      expect(
        segundo.root.children.map((n) => n.delta?.toPlainText() ?? ''),
        primeiro.root.children.map((n) => n.delta?.toPlainText() ?? ''),
      );
    });
  });

  group('edição', () {
    testWidgets('a terceira crase cria o bloco de código', (tester) async {
      final editorState = await _pump(tester, markdownToEditorDocument('``\n'));
      editorState.selection = Selection.collapsed(Position(path: [0], offset: 2));

      expect(await _aciona(tester, codeBlockFromBackticks, editorState), isTrue);
      final node = _nodeAt(editorState.document, 0);
      expect(node.type, CodeBlockKeys.type);
      expect(node.delta!.toPlainText(), isEmpty, reason: 'as crases não ficam');
    });

    testWidgets('crase no meio do texto não cria bloco', (tester) async {
      final editorState =
          await _pump(tester, markdownToEditorDocument('valor de ``\n'));
      editorState.selection =
          Selection.collapsed(Position(path: [0], offset: 'valor de ``'.length));

      expect(await _aciona(tester, codeBlockFromBackticks, editorState), isFalse);
      expect(_nodeAt(editorState.document, 0).type, ParagraphBlockKeys.type);
    });

    testWidgets('Enter dentro do bloco quebra a linha, não o bloco',
        (tester) async {
      final documento = markdownToEditorDocument('# T\n```\nprimeira\n```\n');
      final editorState = await _pump(tester, documento);
      final codigo = editorState.document.root.children
          .indexWhere((n) => n.type == CodeBlockKeys.type);

      editorState.selection = Selection.collapsed(
        Position(path: [codigo], offset: 'primeira'.length),
      );
      expect(await _aciona(tester, newLineInCodeBlock, editorState), isTrue);
      await _digita(tester, editorState, 'segunda');

      final node = _nodeAt(editorState.document, codigo);
      expect(node.type, CodeBlockKeys.type, reason: 'continua sendo código');
      expect(node.delta!.toPlainText(), 'primeira\nsegunda');
      expect(
        editorState.document.root.children
            .where((n) => n.type == CodeBlockKeys.type),
        hasLength(1),
        reason: 'não partiu em dois blocos',
      );
    });

    testWidgets('Enter em linha vazia sai do bloco', (tester) async {
      final documento = markdownToEditorDocument('```\ncodigo\n```\n');
      final editorState = await _pump(tester, documento);
      final codigo = editorState.document.root.children
          .indexWhere((n) => n.type == CodeBlockKeys.type);

      editorState.selection = Selection.collapsed(
        Position(path: [codigo], offset: 'codigo'.length),
      );
      // Primeiro Enter quebra a linha dentro do bloco...
      expect(await _aciona(tester, newLineInCodeBlock, editorState), isTrue);
      // ...e o segundo, já em linha vazia, sai dele.
      expect(await _aciona(tester, newLineInCodeBlock, editorState), isTrue);

      final node = _nodeAt(editorState.document, codigo);
      expect(node.delta!.toPlainText(), 'codigo',
          reason: 'a linha vazia do gatilho não fica no código');
      expect(_nodeAt(editorState.document, codigo + 1).type,
          ParagraphBlockKeys.type);
    });

    testWidgets('formatação automática não age dentro do bloco',
        (tester) async {
      final documento = markdownToEditorDocument('```\n#\n```\n');
      final editorState = await _pump(tester, documento);
      final codigo = editorState.document.root.children
          .indexWhere((n) => n.type == CodeBlockKeys.type);

      // "# " normalmente vira título: é o atalho da própria biblioteca,
      // disparado pelo espaço depois do #.
      final espaco = withoutFormattingInsideCodeBlock(standardCharacterShortcutEvents)
          .where((e) => e.character == ' ');
      expect(espaco, isNotEmpty);

      editorState.selection =
          Selection.collapsed(Position(path: [codigo], offset: 1));
      for (final event in espaco) {
        expect(await _aciona(tester, event, editorState), isFalse,
            reason: 'nenhum atalho de formatação deve agir aqui');
      }

      final node = _nodeAt(editorState.document, codigo);
      expect(node.type, CodeBlockKeys.type, reason: 'não virou título');
      expect(node.delta!.toPlainText(), '#');
    });
  });

  group('aparência', () {
    testWidgets('o texto do bloco usa fonte monoespaçada', (tester) async {
      await _pump(tester, markdownToEditorDocument(_comCodigo));

      final richTexts = tester
          .widgetList<RichText>(find.byType(RichText))
          .where((rt) => rt.text.toPlainText().contains('print("oi")'))
          .toList();
      expect(richTexts, isNotEmpty, reason: 'não achei o texto do bloco');

      // O estilo vive nos spans filhos, não na raiz.
      final fontes = <String?>[];
      richTexts.first.text.visitChildren((span) {
        if (span.style != null) fontes.add(span.style!.fontFamily);
        return true;
      });
      expect(fontes, contains('monospace'),
          reason: 'fontes encontradas: $fontes');
    });

    testWidgets('o bloco tem fundo próprio', (tester) async {
      await _pump(tester, markdownToEditorDocument(_comCodigo));

      // O componente de parágrafo pinta o fundo a partir do atributo do nó.
      final fundos = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.color != null && d.color!.a > 0)
          .toList();
      expect(fundos, isNotEmpty,
          reason: 'nenhum bloco desenhou fundo — o destaque do código sumiu');
    });
  });
}
