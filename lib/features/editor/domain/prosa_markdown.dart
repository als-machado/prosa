import 'package:appflowy_editor/appflowy_editor.dart';

/// Carrega o Markdown de um arquivo do projeto em um documento do editor.
///
/// Faz o que `markdownToDocument` faz e mais uma coisa necessária: quebra em
/// nós separados os parágrafos que vierem com `\n` dentro do delta.
///
/// Por que isso é preciso: ao salvar, o `documentToMarkdown` separa parágrafos
/// por uma única quebra de linha, não por linha em branco. Em Markdown, linhas
/// seguidas sem linha em branco no meio são **um** parágrafo — então o arquivo
/// que o editor acabou de escrever, quando reaberto, volta como um único nó
/// gigante com todas as quebras dentro do delta (medido: um documento de 9 nós
/// reabria com 2).
///
/// E o AppFlowy não sabe lidar com `\n` dentro de um delta: pela API dele, cada
/// quebra é um nó novo. O sintoma é o clique parar de funcionar — clicar no
/// meio do texto joga o cursor para o começo do parágrafo, que num arquivo
/// desses é o topo do documento inteiro.
///
/// Quebrar na carga resolve sem tocar no arquivo: o texto é o mesmo, e salvar
/// de novo produz exatamente as mesmas linhas.
Document markdownToEditorDocument(String markdown) {
  final document = markdownToDocument(markdown);
  final children = document.root.children;
  final normalized = children.expand(_splitOnLineBreaks).toList();
  if (normalized.length == children.length) return document;
  return Document(root: pageNode(children: normalized));
}

/// Tipos de bloco em que a quebra de linha dentro do delta é sempre resultado
/// do Markdown ter juntado linhas seguidas.
///
/// É lista de permissão de propósito: em bloco de código a quebra faz parte do
/// conteúdo, e quebrá-lo transformaria um bloco em vários. (Hoje o parser da
/// biblioteca descarta bloco de código, mas isso pode mudar.)
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
