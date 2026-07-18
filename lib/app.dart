import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/presentation/providers/settings_provider.dart';

class ProsaApp extends ConsumerWidget {
  const ProsaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final isDark = settings?.darkMode ?? false;

    return MaterialApp.router(
      title: 'Prosa',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: appRouter,
      // O menu de busca do AppFlowyEditor (Ctrl+F) lê
      // AppFlowyEditorLocalizations.current internamente (tooltips de
      // regex/case-sensitive) — sem o delegate registrado aqui, essa
      // leitura falha com um assert de estado nulo assim que o menu abre.
      //
      // Não forçamos supportedLocales/locale para pt_BR aqui: o projeto não
      // usa o pacote flutter_localizations, então os delegates padrão do
      // Material/Cupertino (menu de contexto do TextField etc.) só têm
      // fallback em inglês — declarar só pt_BR quebraria esses widgets por
      // não haver um locale em comum entre todos os delegates.
      localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
    );
  }
}
