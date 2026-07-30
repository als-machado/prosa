import 'package:appflowy_editor/appflowy_editor.dart';

import 'code_block.dart';

/// Carrega o Markdown de um arquivo do projeto em um documento do editor.
///
/// Existe porque o `markdownToDocument` da biblioteca não é o inverso do
/// `documentToMarkdown` que o editor usa para salvar. O salvamento escreve
/// **uma linha por bloco**:
///
/// ```text
/// # Título
/// primeiro parágrafo
/// segundo parágrafo
///                     <- parágrafo vazio (linha em branco que o autor digitou)
/// terceiro parágrafo
/// ```
///
/// Lido com as regras normais de Markdown, esse arquivo volta errado de duas
/// maneiras: linhas seguidas viram **um** parágrafo só (com `\n` dentro do
/// delta, que o AppFlowy não sabe posicionar — o clique no texto passa a cair
/// no começo do documento), e a linha em branco desaparece, porque em Markdown
/// ela é separador de parágrafo, não conteúdo.
///
/// Então a leitura aqui é feita por linha, do mesmo jeito que a escrita:
///
/// * linha em branco vira parágrafo vazio;
/// * bloco cercado por ``` vira um nó de código (a biblioteca sabe **escrever**
///   esse bloco, mas não tem parser para ler — sem isto o conteúdo do bloco
///   desaparecia do arquivo no primeiro save depois de abrir);
/// * o resto vai em blocos de linhas seguidas para o parser da biblioteca, que
///   continua cuidando de título, lista, citação, tabela, divisor e da
///   formatação dentro da linha (negrito, itálico, link).
Document markdownToEditorDocument(String markdown) {
  final lines = markdown.split('\n');
  // O arquivo termina com \n; o split gera uma última linha vazia que não é
  // conteúdo.
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();

  final nodes = <Node>[];
  final run = <String>[];

  void flushRun() {
    if (run.isEmpty) return;
    final parsed = markdownToDocument(run.join('\n'));
    nodes.addAll(parsed.root.children.expand(_splitOnLineBreaks));
    run.clear();
  }

  for (var i = 0; i < lines.length; i++) {
    final language = fenceLanguage(lines[i]);
    if (language != null) {
      flushRun();
      final content = <String>[];
      i++;
      while (i < lines.length && fenceLanguage(lines[i]) == null) {
        content.add(lines[i]);
        i++;
      }
      // Se chegou ao fim do arquivo sem fechar a cerca, o conteúdo lido até
      // aqui vale como bloco de código de todo jeito.
      nodes.add(codeBlockNode(content.join('\n'), language: language));
      continue;
    }

    if (lines[i].trim().isEmpty) {
      flushRun();
      nodes.add(paragraphNode());
      continue;
    }

    if (_isThematicBreak(lines[i])) {
      flushRun();
      nodes.add(dividerNode());
      continue;
    }

    run.add(lines[i]);
  }
  flushRun();

  if (nodes.isEmpty) nodes.add(paragraphNode());
  return Document(root: pageNode(children: nodes));
}

/// Linha que é só um divisor: `---`, `***` ou `___`, com três ou mais marcas.
///
/// Precisa ser reconhecida **antes** de a linha entrar no bloco que vai para o
/// parser da biblioteca. É assim que o `documentToMarkdown` escreve o divisor,
/// e em Markdown um `---` logo abaixo de uma linha de texto não é divisor: é
/// título "setext". Sem isto, salvar um divisor depois de um parágrafo e
/// reabrir o arquivo transformava o parágrafo em título e sumia com o divisor
/// — que no livro é a quebra de cena.
bool _isThematicBreak(String line) =>
    RegExp(r'^ {0,3}(-{3,}|\*{3,}|_{3,})\s*$').hasMatch(line);

/// Tipos de bloco em que a quebra de linha dentro do delta só pode ter vindo do
/// Markdown juntando linhas seguidas.
///
/// É lista de permissão de propósito: no bloco de código a quebra é conteúdo.
const _splittableTypes = {ParagraphBlockKeys.type, QuoteBlockKeys.type};

Iterable<Node> _splitOnLineBreaks(Node node) {
  if (!_splittableTypes.contains(node.type)) return [node];
  final delta = node.delta;
  if (delta == null) return [node];
  final text = delta.toPlainText();
  if (!text.contains('\n')) return [node];

  final lines = text.split('\n');
  final nodes = <Node>[];
  var start = 0;
  for (var i = 0; i < lines.length; i++) {
    final end = start + lines[i].length;
    nodes.add(
      Node(
        type: node.type,
        attributes: {
          ...node.attributes,
          blockComponentDelta: delta.slice(start, end).toJson(),
        },
        // Blocos aninhados seguem o último pedaço, que é onde estavam.
        children: i == lines.length - 1 ? node.children : const [],
      ),
    );
    start = end + 1; // pula o \n
  }
  return nodes;
}
