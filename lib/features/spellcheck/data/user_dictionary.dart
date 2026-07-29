import 'dart:io';

import 'word_tokenizer.dart';

/// Palavras aceitas pelo usuário, guardadas **dentro do projeto**.
///
/// Nomes de personagens, lugares inventados e termos do mundo do livro são
/// do livro, não da instalação do Prosa: o arquivo fica na raiz do projeto e
/// entra no Git junto com o texto, então viaja para as outras máquinas e para
/// quem clonar o repositório.
class UserDictionary {
  /// Caminho do arquivo, ou null quando não há projeto aberto (aí o
  /// dicionário funciona só em memória, e nada é persistido).
  final String? filePath;

  final Set<String> _normalized = {};
  final List<String> _words = [];

  UserDictionary({this.filePath});

  /// Palavras como o usuário as escreveu, em ordem alfabética.
  List<String> get words => List.unmodifiable(_words);

  bool get isEmpty => _words.isEmpty;

  static Future<UserDictionary> load(String? filePath) async {
    final dictionary = UserDictionary(filePath: filePath);
    if (filePath == null) return dictionary;

    final file = File(filePath);
    if (!await file.exists()) return dictionary;

    for (final line in await file.readAsLines()) {
      final word = line.trim();
      // Linhas vazias e comentários dão espaço para o usuário organizar o
      // arquivo à mão, já que ele é versionado e legível.
      if (word.isEmpty || word.startsWith('#')) continue;
      dictionary._insert(word);
    }
    return dictionary;
  }

  bool contains(String normalizedWord) => _normalized.contains(normalizedWord);

  Future<void> add(String word) async {
    final trimmed = word.trim();
    if (trimmed.isEmpty) return;
    if (!_insert(trimmed)) return;
    await _persist();
  }

  Future<void> remove(String word) async {
    final normalized = WordTokenizer.normalize(word.trim());
    if (!_normalized.remove(normalized)) return;
    _words.removeWhere((w) => WordTokenizer.normalize(w) == normalized);
    await _persist();
  }

  bool _insert(String word) {
    final normalized = WordTokenizer.normalize(word);
    if (!_normalized.add(normalized)) return false;
    _words
      ..add(word)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return true;
  }

  /// Reescreve o arquivo inteiro, ordenado — assim o diff no Git mostra só a
  /// linha nova, em vez de embaralhar tudo a cada palavra aprendida.
  Future<void> _persist() async {
    final path = filePath;
    if (path == null) return;
    const header =
        '# Palavras aceitas pela verificação ortográfica deste projeto.\n'
        '# Uma por linha. Gerenciado pelo Prosa, editável à mão.\n';
    await File(path).writeAsString('$header${_words.join('\n')}\n');
  }
}
