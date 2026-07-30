import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosa/features/export/data/export_config_store.dart';
import 'package:prosa/features/export/domain/models/export_format.dart';
import 'package:prosa/features/export/presentation/widgets/export_dialog.dart';
import 'package:prosa/features/projects/presentation/providers/project_tree_provider.dart';
import 'package:prosa/shared/models/prosa_project.dart';

late Directory _root;
late ProjectTree _tree;
late ExportConfig _config;

ProsaProject get _project => ProsaProject(
      title: 'O Livro',
      author: 'Ana Autora',
      prosaVersion: '0.2.0',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      localPath: _root.path,
    );

Future<void> _write(String relativePath, String content) async {
  final file = File('${_root.path}/$relativePath');
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

Future<void> _pump(WidgetTester tester) async {
  // A tela padrão do teste (800×600) deixa metade da lista de conteúdo fora
  // do diálogo, e o toque cai no rodapé em vez do item.
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: ExportDialog(project: _project, tree: _tree, config: _config),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    _root = await Directory.systemTemp.createTemp('prosa_dialog_test');
    await _write('chapters/1 - Um/chapter.md', '# Um\nTexto.\n');
    await _write('chapters/2 - Dois/chapter.md', '# Dois\nTexto.\n');
    await _write('characters/Ana/characteristics.md', '# Ana\nAlta.\n');

    // O diálogo recebe tudo pronto — quem abre é que lê o disco.
    final container = ProviderContainer();
    _tree = await container.read(projectTreeProvider(_root.path).future);
    _config = await const ExportConfigStore().load(_project, _tree);
    container.dispose();
  });

  tearDown(() async {
    if (await _root.exists()) await _root.delete(recursive: true);
  });

  testWidgets('projeto novo abre com todos os capítulos marcados e nenhum '
      'apêndice', (tester) async {
    await _pump(tester);

    expect(find.text('1 - Um'), findsOneWidget);
    expect(find.text('2 - Dois'), findsOneWidget);
    expect(find.text('2 capítulos'), findsOneWidget);
  });

  testWidgets('desmarcar um capítulo muda o resumo do rodapé', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('1 - Um'));
    await tester.pumpAndSettle();

    expect(find.text('1 capítulo'), findsOneWidget);
  });

  testWidgets('marcar um apêndice entra na conta', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Sinopse'));
    await tester.pumpAndSettle();

    expect(find.text('2 capítulos, 1 apêndice'), findsOneWidget);
  });

  testWidgets('sem nada marcado, o botão de exportar fica desligado',
      (tester) async {
    await _pump(tester);

    // A caixa do cabeçalho de "Capítulos" desmarca o grupo inteiro.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.text('0 capítulos'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('os metadados vêm do .prosa', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Metadados'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'O Livro'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Ana Autora'), findsOneWidget);
  });

  testWidgets('todos os formatos podem ser escolhidos', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('EPUB'));
    await tester.pumpAndSettle();

    for (final format in ExportFormat.values) {
      expect(find.text(format.label), findsWidgets, reason: format.label);
      expect(find.text('${format.label} — em breve'), findsNothing);
    }
  });

  testWidgets('trocar para TXT esconde a aba de capa', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('EPUB'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TXT').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Capa'));
    await tester.pumpAndSettle();

    expect(find.textContaining('não tem capa'), findsOneWidget);
  });
}
