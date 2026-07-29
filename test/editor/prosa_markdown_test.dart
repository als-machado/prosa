import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosa/features/editor/domain/prosa_markdown.dart';

/// Um arquivo escrito pelo próprio editor: linhas seguidas, sem linha em branco
/// entre elas, porque é assim que o documentToMarkdown salva parágrafos.
const _arquivoDoEditor = '''
# Resumo da Camada 1
capítulo 1:
Infância do narrador, na inocência da infância, descobre o amor.
O narrador, por ser cinco anos mais velho que a Camila, a via como um bebê.
capítulo 2:
Narrador faz dezoito anos e tem uma pequena crise existencial.
''';

List<String> _textos(Document document) => document.root.children
    .map((n) => n.delta?.toPlainText() ?? '')
    .toList();

Future<EditorState> _pump(WidgetTester tester, Document document) async {
  final editorState = EditorState(document: document);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1020,
          height: 700,
          child: AppFlowyEditor(
            editorState: editorState,
            editorStyle: const EditorStyle.desktop(
              padding: EdgeInsets.symmetric(horizontal: 80),
              textStyleConfiguration:
                  TextStyleConfiguration(text: TextStyle(fontSize: 16, height: 1.8)),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return editorState;
}

void main() {
  group('markdownToEditorDocument', () {
    test('quebra em um nó por linha o que a biblioteca junta num só', () {
      // O parser da biblioteca junta tudo: linha seguida de linha, em Markdown,
      // é um parágrafo só.
      final cru = markdownToDocument(_arquivoDoEditor);
      expect(cru.root.children.length, 2);
      expect(cru.root.children[1].delta!.toPlainText(), contains('\n'));

      final documento = markdownToEditorDocument(_arquivoDoEditor);
      expect(documento.root.children.length, 6);
      for (final node in documento.root.children) {
        expect(node.delta?.toPlainText() ?? '', isNot(contains('\n')),
            reason: 'nenhum delta pode conter quebra de linha');
      }
    });

    test('preserva o texto, caractere a caractere', () {
      final documento = markdownToEditorDocument(_arquivoDoEditor);
      // Uma linha do arquivo = um nó, com o mesmo texto. O `# ` do título é
      // marcação, não texto.
      final esperado = _arquivoDoEditor.trimRight().split('\n');
      esperado[0] = esperado[0].replaceFirst('# ', '');
      expect(_textos(documento), esperado);
    });

    test('preserva o tipo do bloco', () {
      final documento = markdownToEditorDocument(_arquivoDoEditor);
      expect(documento.root.children.first.type, HeadingBlockKeys.type);
      expect(documento.root.children[1].type, ParagraphBlockKeys.type);
    });

    test('não mexe em arquivo que já tem parágrafos separados', () {
      const comLinhasEmBranco = '# Título\n\nprimeiro parágrafo\n\nsegundo parágrafo\n';
      final documento = markdownToEditorDocument(comLinhasEmBranco);
      expect(_textos(documento), ['Título', 'primeiro parágrafo', 'segundo parágrafo']);
    });

    test('salvar e reabrir dá o mesmo documento (round-trip estável)', () {
      // Esta é a garantia que faltava: sem a quebra na carga, cada ciclo de
      // salvar/reabrir colapsava o documento inteiro em um nó.
      final primeiro = markdownToEditorDocument(_arquivoDoEditor);
      final segundo = markdownToEditorDocument(documentToMarkdown(primeiro));
      expect(_textos(segundo), _textos(primeiro));
      final terceiro = markdownToEditorDocument(documentToMarkdown(segundo));
      expect(_textos(terceiro), _textos(primeiro));
    });

    test('citação de várias linhas também vira um nó por linha', () {
      // O parser junta as duas linhas num só nó de citação, com \n no delta —
      // mesmo problema do parágrafo.
      const comCitacao = '# T\n\n> primeira linha\n> segunda linha\n';
      final documento = markdownToEditorDocument(comCitacao);
      final citacoes = documento.root.children
          .where((n) => n.type == QuoteBlockKeys.type)
          .toList();
      expect(citacoes, hasLength(2));
      expect(citacoes.map((n) => n.delta!.toPlainText()),
          ['primeira linha', 'segunda linha']);
    });

    test('lista não é tocada', () {
      const comLista = '# T\n\n- item um\n- item dois\n';
      final documento = markdownToEditorDocument(comLista);
      expect(
        documento.root.children.where((n) => n.type == BulletedListBlockKeys.type),
        hasLength(2),
      );
    });

    test('mantém formatação inline ao quebrar', () {
      const comNegrito = '# T\numa linha com **negrito** aqui\noutra linha\n';
      final documento = markdownToEditorDocument(comNegrito);
      final linha = documento.root.children[1];
      expect(linha.delta!.toPlainText(), 'uma linha com negrito aqui');
      final temNegrito = linha.delta!.whereType<TextInsert>().any(
            (op) => op.attributes?[AppFlowyRichTextKeys.bold] == true,
          );
      expect(temNegrito, isTrue, reason: 'o negrito sobreviveu à quebra');
    });
  });

  group('clique no texto', () {
    testWidgets('cai na linha clicada, não no começo do documento',
        (tester) async {
      final editorState =
          await _pump(tester, markdownToEditorDocument(_arquivoDoEditor));

      // Clica na área das últimas linhas. Com o documento colapsado num nó
      // só, cliques assim caíam no offset 0 do parágrafo gigante — que é o
      // topo do documento, logo abaixo do título.
      final caminhos = <Path>[];
      for (final y in [120.0, 160.0, 200.0]) {
        await tester.tapAt(Offset(500, y));
        await tester.pumpAndSettle();
        final selection = editorState.selection;
        expect(selection, isNotNull);
        caminhos.add(selection!.start.path);
      }
      // Cliques em alturas diferentes têm de cair em nós diferentes.
      expect(caminhos.toSet().length, greaterThan(1),
          reason: 'todos os cliques caíram no mesmo nó: $caminhos');
      expect(caminhos, everyElement(isNot([0])),
          reason: 'algum clique caiu no título: $caminhos');
    });
  });
}
