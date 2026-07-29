import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';

import '../data/spell_checker.dart';
import '../domain/models/misspelling.dart';

class _NodeSpelling {
  final String text;
  final List<Misspelling> misspellings;
  const _NodeSpelling(this.text, this.misspellings);
}

/// Mantém o resultado da verificação por parágrafo e decide o que o editor
/// deve sublinhar.
///
/// A verificação roda sob demanda, no momento em que o parágrafo é
/// desenhado, e o resultado fica em cache com o texto que o gerou. Como o
/// AppFlowy já reconstrói o parágrafo editado a cada tecla, isso dá
/// verificação "conforme se escreve" sem timer, sem debounce e sem observar
/// transações: se o texto mudou, o cache não serve e a conta é refeita (uns
/// poucos microssegundos por parágrafo).
///
/// Nada é escrito no documento. A marcação é só de renderização — gravar
/// atributo no delta sujaria o Markdown salvo, a pilha de desfazer e o
/// autosave.
class SpellcheckHighlighter extends ChangeNotifier {
  SpellChecker? _checker;
  EditorState? _editorState;

  final Map<String, _NodeSpelling> _cache = {};

  /// Palavra que está sendo digitada agora: fica sem sublinhado até o cursor
  /// sair dela, senão o editor rabisca cada palavra no meio da digitação.
  Node? _typingNode;
  Misspelling? _typingWord;

  SpellChecker? get checker => _checker;

  bool get isEnabled => _checker != null;

  set checker(SpellChecker? value) {
    if (_checker == value) return;
    _checker = value;
    invalidate();
  }

  /// Liga o destacador ao documento aberto. Chamar a cada troca de arquivo.
  void attach(EditorState editorState) {
    if (_editorState == editorState) return;
    _editorState?.selectionNotifier.removeListener(_onSelectionChanged);
    _editorState = editorState;
    _clearState();
    editorState.selectionNotifier.addListener(_onSelectionChanged);
  }

  void detach() {
    _editorState?.selectionNotifier.removeListener(_onSelectionChanged);
    _editorState = null;
    _clearState();
  }

  /// Descarta o cache e manda o documento inteiro se repintar. Usado quando o
  /// idioma muda ou quando uma palavra é aprendida/ignorada.
  void invalidate() {
    _clearState();
    _repaintDocument();
    notifyListeners();
  }

  void _clearState() {
    _cache.clear();
    _typingNode = null;
    _typingWord = null;
  }

  /// O que o decorador deve sublinhar neste parágrafo.
  List<Misspelling> visibleFor(Node node) {
    final found = _forNode(node);
    if (found.isEmpty) return found;
    return _withoutWordBeingTyped(node, found);
  }

  /// Erro sob um deslocamento do parágrafo, inclusive o da palavra que está
  /// sendo digitada — é o que o menu de contexto precisa quando o usuário
  /// clica com o botão direito exatamente sobre ela.
  Misspelling? at(Node node, int offset) {
    for (final misspelling in _forNode(node)) {
      if (misspelling.contains(offset)) return misspelling;
    }
    return null;
  }

  List<Misspelling> _forNode(Node node) {
    final checker = _checker;
    if (checker == null) return const [];
    final delta = node.delta;
    if (delta == null) return const [];

    final text = delta.toPlainText();
    final cached = _cache[node.id];
    if (cached != null && cached.text == text) return cached.misspellings;

    final misspellings = checker.check(text);
    _cache[node.id] = _NodeSpelling(text, misspellings);
    return misspellings;
  }

  List<Misspelling> _withoutWordBeingTyped(
    Node node,
    List<Misspelling> found,
  ) {
    final selection = _editorState?.selection;
    if (selection == null || !selection.isCollapsed) return found;
    if (!selection.start.path.equals(node.path)) return found;

    final offset = selection.start.offset;
    final index = found.indexWhere((m) => m.contains(offset));
    if (index < 0) {
      // O cursor está neste parágrafo, mas não em cima de erro nenhum: o
      // registro anterior não vale mais.
      if (_typingNode == node) {
        _typingNode = null;
        _typingWord = null;
      }
      return found;
    }

    _typingNode = node;
    _typingWord = found[index];
    return [...found.take(index), ...found.skip(index + 1)];
  }

  /// O cursor sair da palavra não muda o texto, então o AppFlowy não
  /// reconstrói o parágrafo por conta própria — sem este empurrão, a palavra
  /// que ficou errada continuaria sem sublinhado.
  void _onSelectionChanged() {
    final node = _typingNode;
    final word = _typingWord;
    if (node == null || word == null) return;

    final selection = _editorState?.selection;
    final stillTyping = selection != null &&
        selection.isCollapsed &&
        selection.start.path.equals(node.path) &&
        word.contains(selection.start.offset);
    if (stillTyping) return;

    _typingNode = null;
    _typingWord = null;
    // O aviso de seleção chega no meio do tratamento do evento de entrada;
    // repintar agora derrubaria a árvore de widgets durante o despacho.
    scheduleMicrotask(node.notify);
  }

  void _repaintDocument() {
    final editorState = _editorState;
    if (editorState == null) return;
    scheduleMicrotask(() {
      for (final node in _descendants(editorState.document.root)) {
        node.notify();
      }
    });
  }

  Iterable<Node> _descendants(Node root) sync* {
    for (final child in root.children) {
      yield child;
      yield* _descendants(child);
    }
  }

  @override
  void dispose() {
    _editorState?.selectionNotifier.removeListener(_onSelectionChanged);
    super.dispose();
  }
}
