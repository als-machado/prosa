import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import '../../../settings/domain/models/app_settings.dart';

/// O arquivo do jeito que ele está no disco: Markdown como texto.
///
/// É a outra metade do botão de alternar visão. Serve para ver a marcação que
/// o editor esconde — a linha da tabela, o link, a cerca do bloco de código —
/// e para consertar à mão o que a edição visual não alcança.
///
/// A fonte é monoespaçada e a numeração de linha aparece porque, no formato do
/// Prosa, **uma linha é um bloco**: número de linha aqui é número de parágrafo.
class RawMarkdownEditor extends StatelessWidget {
  final CodeLineEditingController controller;
  final CodeFindController findController;
  final AppSettings settings;
  final VoidCallback onSave;

  const RawMarkdownEditor({
    super.key,
    required this.controller,
    required this.findController,
    required this.settings,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return CallbackShortcuts(
      // O Ctrl+S do modo renderizado vem do AppFlowy; aqui ele precisa de
      // dono próprio, senão salvar deixaria de funcionar só por causa da
      // troca de visão.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): onSave,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): onSave,
      },
      child: Container(
        color: theme.scaffoldBackgroundColor,
        child: CodeEditor(
          controller: controller,
          findController: findController,
          // O Prosa escreve um parágrafo inteiro por linha; sem quebra
          // automática, ler o texto viraria rolagem horizontal.
          wordWrap: true,
          padding: EdgeInsets.symmetric(
            horizontal: settings.editorMarginHorizontal,
            vertical: 16,
          ),
          indicatorBuilder: (context, editingController, chunkController, notifier) {
            return Row(
              children: [
                DefaultCodeLineNumber(
                  controller: editingController,
                  notifier: notifier,
                  textStyle: TextStyle(
                    fontSize: settings.editorFontSize - 2,
                    color: colorScheme.outline,
                  ),
                  focusedTextStyle: TextStyle(
                    fontSize: settings.editorFontSize - 2,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
              ],
            );
          },
          findBuilder: (context, findController, readOnly) =>
              _FindPanel(controller: findController, readOnly: readOnly),
          style: CodeEditorStyle(
            fontSize: settings.editorFontSize,
            fontHeight: 1.5,
            fontFamily: 'monospace',
            textColor: colorScheme.onSurface,
            backgroundColor: Colors.transparent,
            cursorColor: colorScheme.primary,
            selectionColor: colorScheme.primary.withValues(alpha: 0.2),
            chunkIndicatorColor: colorScheme.outline,
            codeTheme: CodeHighlightTheme(
              languages: {
                'markdown': CodeHighlightThemeMode(mode: langMarkdown),
              },
              theme: dark ? atomOneDarkTheme : atomOneLightTheme,
            ),
          ),
        ),
      ),
    );
  }
}

/// Painel de busca do modo texto.
///
/// O `re_editor` já liga o Ctrl+F e faz a busca; o que ele não traz é a
/// barra. Sem esta, a tecla ficaria muda justamente no modo em que se vem
/// procurar alguma coisa.
class _FindPanel extends StatelessWidget implements PreferredSizeWidget {
  final CodeFindController controller;
  final bool readOnly;

  const _FindPanel({required this.controller, required this.readOnly});

  static const _height = 48.0;
  static const _heightWithReplace = 92.0;

  @override
  Size get preferredSize => Size.fromHeight(
        controller.value?.replaceMode == true ? _heightWithReplace : _height,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = controller.value;
    if (value == null) return const SizedBox.shrink();

    final result = value.result;
    final matches = result?.matches.length ?? 0;
    final position = (result?.index ?? -1) + 1;

    return Material(
      color: theme.colorScheme.surfaceContainer,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _input(
                    context,
                    controller.findInputController,
                    controller.findInputFocusNode,
                    'Buscar',
                    onSubmitted: (_) => controller.nextMatch(),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  matches == 0 ? 'nenhum' : '$position de $matches',
                  style: theme.textTheme.bodySmall,
                ),
                _iconButton(Icons.arrow_upward, 'Anterior',
                    matches == 0 ? null : controller.previousMatch),
                _iconButton(Icons.arrow_downward, 'Próximo',
                    matches == 0 ? null : controller.nextMatch),
                _iconButton(
                  Icons.text_fields,
                  'Diferenciar maiúsculas',
                  controller.toggleCaseSensitive,
                  isActive: value.option.caseSensitive,
                ),
                if (!readOnly)
                  _iconButton(
                    Icons.find_replace,
                    'Substituir',
                    controller.toggleMode,
                    isActive: value.replaceMode,
                  ),
                _iconButton(Icons.close, 'Fechar', controller.close),
              ],
            ),
            if (value.replaceMode && !readOnly) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _input(
                      context,
                      controller.replaceInputController,
                      controller.replaceInputFocusNode,
                      'Substituir por',
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: matches == 0 ? null : controller.replaceMatch,
                    child: const Text('Substituir'),
                  ),
                  TextButton(
                    onPressed: matches == 0 ? null : controller.replaceAllMatches,
                    child: const Text('Todas'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _input(
    BuildContext context,
    TextEditingController controller,
    FocusNode focusNode,
    String label, {
    ValueChanged<String>? onSubmitted,
  }) {
    return SizedBox(
      height: 34,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onSubmitted: onSubmitted,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
    );
  }

  Widget _iconButton(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    bool isActive = false,
  }) {
    return Builder(
      builder: (context) => IconButton(
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        color: isActive ? Theme.of(context).colorScheme.primary : null,
      ),
    );
  }
}
