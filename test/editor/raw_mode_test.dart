import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosa/features/editor/presentation/providers/editor_provider.dart';
import 'package:prosa/features/editor/presentation/screens/editor_screen.dart';
import 'package:prosa/features/editor/presentation/widgets/raw_markdown_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Um arquivo do jeito que o editor salva: uma linha por bloco.
const _conteudo = '# A partida\n'
    'Era uma vez um rei.\n'
    'A rainha morava longe.\n';

late File _arquivo;

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(EditorScreen)));

RawMarkdownEditor _raw(WidgetTester tester) =>
    tester.widget<RawMarkdownEditor>(find.byType(RawMarkdownEditor));

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeFileProvider.overrideWith((ref) => _arquivo.path),
        // Sem tocar no disco na carga: o teste controla o que o editor abre.
        fileContentProvider.overrideWith((ref) async => _conteudo),
      ],
      child: const MaterialApp(home: EditorScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _alternar(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
}

const _paraTexto = 'Ver o Markdown como texto';
const _paraFormatado = 'Voltar ao texto formatado';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _arquivo = File(
      '${Directory.systemTemp.createTempSync('prosa_raw').path}/capitulo.md',
    );
    await _arquivo.writeAsString(_conteudo);
  });

  tearDown(() async {
    final dir = _arquivo.parent;
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  testWidgets('o botão troca entre o editor formatado e o texto',
      (tester) async {
    await _pump(tester);

    expect(find.byType(AppFlowyEditor), findsOneWidget);
    expect(find.byType(RawMarkdownEditor), findsNothing);

    await _alternar(tester, _paraTexto);
    expect(find.byType(RawMarkdownEditor), findsOneWidget);
    expect(find.byType(AppFlowyEditor), findsNothing);

    await _alternar(tester, _paraFormatado);
    expect(find.byType(AppFlowyEditor), findsOneWidget);
    expect(find.byType(RawMarkdownEditor), findsNothing);
  });

  testWidgets('o modo texto mostra o Markdown, com a marcação à mostra',
      (tester) async {
    await _pump(tester);
    await _alternar(tester, _paraTexto);

    // Verbatim, inclusive a linha final: é o arquivo, não uma releitura dele.
    expect(_raw(tester).controller.text, _conteudo);
  });

  testWidgets('ir e voltar não perde parágrafo nem inventa alteração',
      (tester) async {
    await _pump(tester);
    final container = _container(tester);
    expect(container.read(editorNotifierProvider), isFalse);

    await _alternar(tester, _paraTexto);
    await _alternar(tester, _paraFormatado);

    // O documento continua com os mesmos blocos, e o arquivo continua salvo:
    // olhar o texto não é editar.
    final state = tester
        .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
        .editorState;
    expect(
      state.document.root.children.map((n) => n.delta?.toPlainText()),
      ['A partida', 'Era uma vez um rei.', 'A rainha morava longe.'],
    );
    expect(container.read(editorNotifierProvider), isFalse);
  });

  testWidgets('editar no modo texto marca alteração pendente', (tester) async {
    await _pump(tester);
    await _alternar(tester, _paraTexto);
    final container = _container(tester);
    expect(container.read(editorNotifierProvider), isFalse);

    _raw(tester).controller.text = '$_conteudo O rei morreu.\n';
    await tester.pump();

    expect(container.read(editorNotifierProvider), isTrue);

    // Deixa o autosave disparar: sem isso o teste termina com o temporizador
    // dele pendente, e o binding reclama.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('o que foi escrito no modo texto vai para o editor formatado',
      (tester) async {
    await _pump(tester);
    await _alternar(tester, _paraTexto);

    _raw(tester).controller.text =
        '# Outro título\nParágrafo novo.\nE mais um.\n';
    await tester.pump();
    await _alternar(tester, _paraFormatado);

    final state = tester
        .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
        .editorState;
    expect(
      state.document.root.children.map((n) => n.delta?.toPlainText()),
      ['Outro título', 'Parágrafo novo.', 'E mais um.'],
    );
    expect(state.document.root.children.first.type, HeadingBlockKeys.type);

    // Alternar a visão não salva: o "por salvar" tem de sobreviver à troca,
    // senão o texto escrito no modo texto se perderia.
    expect(_container(tester).read(editorNotifierProvider), isTrue);
  });

  testWidgets('no modo texto os botões de formatação ficam desligados',
      (tester) async {
    await _pump(tester);

    IconButton botao(IconData icone) => tester.widget<IconButton>(
          find.ancestor(
            of: find.byIcon(icone),
            matching: find.byType(IconButton),
          ),
        );

    expect(botao(Icons.format_bold).onPressed, isNotNull);

    await _alternar(tester, _paraTexto);
    // Negrito e título agiriam sobre o documento escondido, e o resultado
    // seria descartado na volta.
    expect(botao(Icons.format_bold).onPressed, isNull);
    expect(botao(Icons.title).onPressed, isNull);
  });
}
