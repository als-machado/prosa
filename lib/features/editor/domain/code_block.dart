import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// Bloco de código.
///
/// A biblioteca sabe **escrever** um nó deste tipo em Markdown (o
/// `CodeBlockNodeParser` do `documentToMarkdown` transforma em cerca de três
/// crases), mas não tem parser de leitura nem componente de tela para ele —
/// resultado: bloco de código escrito no arquivo desaparecia ao abrir, e o
/// primeiro save depois disso apagava o conteúdo. A leitura está em
/// `markdownToEditorDocument`; desenhar e editar está aqui.
class CodeBlockKeys {
  CodeBlockKeys._();

  /// Precisa ser exatamente 'code': é o tipo que o encoder da biblioteca espera.
  static const String type = 'code';

  /// Linguagem escrita depois da cerca de abertura (```dart). Opcional.
  static const String language = 'language';
}

/// Fundo do bloco: cinza translúcido, que escurece de leve o tema claro e
/// clareia de leve o escuro, sem precisar saber qual está em uso.
const String _codeBackground = '0x14808080';

/// Devolve a linguagem quando a linha é uma cerca de código (string vazia
/// quando a cerca não traz linguagem), ou null quando não é linha de cerca.
String? fenceLanguage(String line) {
  final trimmed = line.trimLeft();
  if (!trimmed.startsWith('```')) return null;
  return trimmed.substring(3).trim();
}

Node codeBlockNode(String code, {String language = ''}) => Node(
      type: CodeBlockKeys.type,
      attributes: {
        blockComponentDelta: (Delta()..insert(code)).toJson(),
        if (language.isNotEmpty) CodeBlockKeys.language: language,
        // O componente de parágrafo pinta o fundo a partir deste atributo. Ele
        // não vai para o arquivo: o encoder escreve só o delta e a linguagem.
        blockComponentBackgroundColor: _codeBackground,
      },
    );

bool _isCodeBlock(Node? node) => node?.type == CodeBlockKeys.type;

/// Componente de tela do bloco de código.
///
/// Reaproveita o componente de parágrafo — que já traz cursor, seleção, arrastar
/// e o fundo vindo do atributo — trocando o estilo do texto por monoespaçado.
BlockComponentBuilder codeBlockComponentBuilder({
  required double fontSize,
  required Color textColor,
}) {
  return ParagraphBlockComponentBuilder(
    configuration: BlockComponentConfiguration(
      padding: (_) => const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      placeholderText: (_) => '',
      textStyle: (_, {TextSpan? textSpan}) => TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: const ['DejaVu Sans Mono', 'Courier New'],
        fontSize: fontSize - 1,
        height: 1.45,
        color: textColor,
      ),
    ),
  );
}

/// Ao digitar a terceira crase numa linha vazia, transforma o parágrafo em
/// bloco de código.
///
/// Sem isto não haveria como criar um bloco pelo editor: a cerca só viraria
/// bloco ao reabrir o arquivo.
CharacterShortcutEvent get codeBlockFromBackticks => CharacterShortcutEvent(
      key: 'format triple backtick to code block',
      character: '`',
      handler: (editorState) => formatMarkdownSymbol(
        editorState,
        // Só numa linha que tem exatamente as duas crases anteriores, para não
        // engolir crase digitada no meio do texto.
        (node) => !_isCodeBlock(node) && node.delta?.toPlainText() == '``',
        (_, text, _) => text == '``',
        (_, _, _) => [codeBlockNode('')],
      ),
    );

/// Enter dentro do bloco de código quebra a linha em vez de criar bloco novo.
///
/// Em linha vazia no fim do bloco, sai dele: é a única saída pelo teclado
/// quando o bloco é o último do documento.
CharacterShortcutEvent get newLineInCodeBlock => CharacterShortcutEvent(
      key: 'insert new line in code block',
      character: '\n',
      handler: (editorState) async {
        final selection = editorState.selection;
        if (selection == null || !selection.isCollapsed) return false;
        final node = editorState.getNodeAtPath(selection.start.path);
        if (!_isCodeBlock(node)) return false;
        final delta = node!.delta;
        if (delta == null) return false;

        final offset = selection.start.offset;
        final text = delta.toPlainText();

        if (offset == text.length && (text.isEmpty || text.endsWith('\n'))) {
          final transaction = editorState.transaction;
          // Tira a linha vazia que serviu de gatilho.
          if (text.endsWith('\n')) {
            transaction.deleteText(node, text.length - 1, 1);
          }
          final next = node.path.next;
          transaction
            ..insertNode(next, paragraphNode())
            ..afterSelection = Selection.collapsed(Position(path: next));
          await editorState.apply(transaction);
          return true;
        }

        final transaction = editorState.transaction
          ..insertText(node, offset, '\n')
          ..afterSelection = Selection.collapsed(
            Position(path: node.path, offset: offset + 1),
          );
        await editorState.apply(transaction);
        return true;
      },
    );

/// Desliga, dentro do bloco de código, os atalhos que reformatam o texto.
///
/// Sem isto, digitar `# ` ou `- ` dentro do bloco viraria título ou lista, e o
/// conteúdo do código seria alterado sozinho.
List<CharacterShortcutEvent> withoutFormattingInsideCodeBlock(
  List<CharacterShortcutEvent> events,
) {
  return events
      .map(
        (event) => CharacterShortcutEvent(
          key: event.key,
          character: event.character,
          handler: (editorState) async {
            final selection = editorState.selection;
            if (selection != null) {
              final node = editorState.getNodeAtPath(selection.start.path);
              if (_isCodeBlock(node)) return false;
            }
            return event.handler(editorState);
          },
        ),
      )
      .toList();
}
