import '../domain/models/spell_language.dart';
import 'word_tokenizer.dart';

/// Propõe correções para uma palavra desconhecida.
///
/// O filtro de Bloom só responde "existe?", não dá para procurar palavras
/// parecidas dentro dele. A saída é inverter o problema: gerar os candidatos
/// — as palavras que um erro comum produziria — e perguntar por cada um. São
/// alguns milhares de consultas, cada uma dois hashes e alguns bits: sai em
/// poucos milissegundos.
class SuggestionGenerator {
  final SpellLanguage language;

  /// Decide se um candidato serve como sugestão. Toda a política de
  /// dicionário fica do lado do corretor: palavra composta validada pedaço
  /// por pedaço, palavra aprendida no projeto valendo mesmo sem parecer
  /// possível no idioma, e o modelo de plausibilidade descartando o que só
  /// "existe" por falso positivo do filtro.
  final bool Function(String candidate) accept;

  /// Ordem de exibição. O erro de acento é o mais comum de quem escreve em
  /// português, então vem primeiro; palavra emendada e letra sobrando ficam
  /// no fim, onde atrapalham menos.
  static const _rankDiacritic = 0;
  static const _rankPhonetic = 1;
  static const _rankTransposition = 1;
  static const _rankDoubledLetter = 1;
  static const _rankSubstitution = 2;
  static const _rankLikelySplit = 2;
  static const _rankDeletion = 3;
  static const _rankInsertion = 4;
  static const _rankSplit = 5;

  /// Teto de variantes de acento por palavra: sem ele, uma palavra longa e
  /// cheia de vogais gera um produto cartesiano enorme.
  static const _diacriticLimit = 4096;

  /// Teto por variante fonética ao combinar as duas coisas. São dezenas de
  /// variantes fonéticas por palavra, então o teto aqui é bem menor.
  static const _composedDiacriticLimit = 256;

  /// Uma metade de palavra emendada só é convincente com este tamanho. Abaixo
  /// disso a sugestão vai para o fim da lista ("sussu rou" não ajuda ninguém).
  static const _convincingSplit = 4;

  /// Letra -> todas as letras do seu grupo de acentuação (`a` -> `aáàâã`).
  final Map<String, String> _diacritics;

  SuggestionGenerator({
    required this.language,
    required this.accept,
  }) : _diacritics = _buildDiacriticMap(language.diacriticGroups);

  static Map<String, String> _buildDiacriticMap(List<String> groups) {
    final map = <String, String>{};
    for (final group in groups) {
      for (final letter in group.split('')) {
        map[letter] = group;
      }
    }
    return map;
  }

  List<String> suggest(String word, {int limit = 7}) {
    final target = WordTokenizer.normalize(word);
    if (target.length < 2) return const [];

    final ranks = <String, int>{};
    void offer(String candidate, int rank) {
      if (candidate == target || candidate.length < 2) return;
      final current = ranks[candidate];
      if (current == null || rank < current) ranks[candidate] = rank;
    }

    for (final variant in _diacriticVariants(target)) {
      offer(variant, _rankDiacritic);
    }
    for (final variant in _phoneticVariants(target)) {
      offer(variant, _rankPhonetic);
      // Os dois erros costumam vir juntos: "atravez" precisa de z→s **e** de
      // e→ê para chegar em "através".
      for (final accented
          in _diacriticVariants(variant, limit: _composedDiacriticLimit)) {
        offer(accented, _rankPhonetic);
      }
    }
    for (final variant in _transpositions(target)) {
      offer(variant, _rankTransposition);
    }
    for (final variant in _substitutions(target)) {
      offer(variant, _rankSubstitution);
    }
    _forEachDeletion(target, offer);
    for (final variant in _insertions(target)) {
      offer(variant, _rankInsertion);
    }
    _forEachSplit(target, offer);

    final accepted = <String>[];
    for (final candidate in ranks.keys) {
      if (accept(candidate)) accepted.add(candidate);
    }

    accepted.sort((a, b) {
      final byRank = ranks[a]!.compareTo(ranks[b]!);
      return byRank != 0 ? byRank : a.compareTo(b);
    });

    return accepted
        .take(limit)
        .map((suggestion) => _matchCase(word, suggestion))
        .toList();
  }

  /// Todas as combinações de acentuação das letras da palavra. É o que faz
  /// "chapeu" virar "chapéu" e "orgao" virar "órgão" — duas trocas de uma vez,
  /// que a geração por edição simples nunca alcançaria.
  Iterable<String> _diacriticVariants(String word, {int? limit}) {
    final ceiling = limit ?? _diacriticLimit;
    var variants = <String>[''];
    for (final letter in word.split('')) {
      final group = _diacritics[letter];
      if (group == null ||
          group.length < 2 ||
          variants.length * group.length > ceiling) {
        // Sem variação (ou já grande demais): segue com a letra original.
        variants = [for (final prefix in variants) prefix + letter];
        continue;
      }
      variants = [
        for (final prefix in variants)
          for (final option in group.split('')) prefix + option,
      ];
    }
    return variants;
  }

  /// Aplica cada regra fonética do idioma em cada posição onde ela casa, uma
  /// por vez. "recomendasao" → "recomendação" numa tacada.
  Iterable<String> _phoneticVariants(String word) {
    final variants = <String>[];
    for (final (from, to) in language.phoneticRules) {
      var index = word.indexOf(from);
      while (index >= 0) {
        variants.add(
          word.substring(0, index) + to + word.substring(index + from.length),
        );
        index = word.indexOf(from, index + 1);
      }
    }
    return variants;
  }

  /// Letra sobrando. Quando a letra removida estava duplicada ("casaa"), a
  /// correção é quase certa e sobe na lista.
  void _forEachDeletion(String word, void Function(String, int) offer) {
    for (var i = 0; i < word.length; i++) {
      final candidate = word.substring(0, i) + word.substring(i + 1);
      final doubled = (i > 0 && word[i] == word[i - 1]) ||
          (i + 1 < word.length && word[i] == word[i + 1]);
      offer(candidate, doubled ? _rankDoubledLetter : _rankDeletion);
    }
  }

  /// Espaço esquecido: "casaverde" → "casa verde". As duas metades são
  /// testadas aqui para não encher a lista de recortes sem sentido.
  void _forEachSplit(String word, void Function(String, int) offer) {
    for (var i = 2; i <= word.length - 2; i++) {
      final left = word.substring(0, i);
      final right = word.substring(i);
      if (!accept(left) || !accept(right)) continue;
      final convincing = left.length >= _convincingSplit &&
          right.length >= _convincingSplit;
      offer('$left $right', convincing ? _rankLikelySplit : _rankSplit);
    }
  }

  Iterable<String> _transpositions(String word) => [
        for (var i = 0; i < word.length - 1; i++)
          word.substring(0, i) + word[i + 1] + word[i] + word.substring(i + 2),
      ];

  Iterable<String> _substitutions(String word) => [
        for (var i = 0; i < word.length; i++)
          for (final letter in language.alphabet.split(''))
            if (letter != word[i])
              word.substring(0, i) + letter + word.substring(i + 1),
      ];

  Iterable<String> _insertions(String word) => [
        for (var i = 0; i <= word.length; i++)
          for (final letter in language.alphabet.split(''))
            word.substring(0, i) + letter + word.substring(i),
      ];

  /// Devolve a sugestão com a mesma "roupa" da palavra original: se o usuário
  /// escreveu `Chapeu`, a correção sai `Chapéu`, não `chapéu`.
  static String _matchCase(String original, String suggestion) {
    if (original.toUpperCase() == original && original.length > 1) {
      return suggestion.toUpperCase();
    }
    final first = original.substring(0, 1);
    if (first.toUpperCase() == first && first.toLowerCase() != first) {
      return suggestion.substring(0, 1).toUpperCase() + suggestion.substring(1);
    }
    return suggestion;
  }
}
