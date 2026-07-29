import '../domain/models/misspelling.dart';
import '../domain/models/spell_language.dart';
import 'bloom_dictionary.dart';
import 'plausibility_model.dart';
import 'suggestion_generator.dart';
import 'user_dictionary.dart';
import 'word_tokenizer.dart';

/// Verificação ortográfica de um trecho de texto.
///
/// É síncrono de propósito: consultar o filtro de Bloom é aritmética sobre um
/// vetor de bits, e um parágrafo inteiro sai em microssegundos. Isolate aqui
/// só adicionaria latência e complexidade.
class SpellChecker {
  final BloomDictionary dictionary;
  final SpellLanguage language;
  final UserDictionary userDictionary;

  /// Só melhora as sugestões; a checagem do texto não usa (ver
  /// [PlausibilityModel]).
  final PlausibilityModel? plausibility;

  /// Palavras que o usuário mandou ignorar nesta sessão, sem gravar no
  /// dicionário do projeto.
  final Set<String> _ignored = {};

  late final SuggestionGenerator _suggestions;

  SpellChecker({
    required this.dictionary,
    required this.language,
    required this.userDictionary,
    this.plausibility,
  }) {
    _suggestions = SuggestionGenerator(
      language: language,
      accept: _acceptSuggestion,
    );
  }

  /// Pedaços que existem no português apenas colados por hífen: pronomes
  /// oblíquos da ênclise (`chamá-lo`, `diz-se`) e as terminações de futuro e
  /// condicional da mesóclise (`dar-te-ei`, `dar-te-íamos`). Também cobre as
  /// siglas de estado que aparecem em topônimos (`Aracaju-SE`).
  ///
  /// A mesma lista está em `HYPHEN_GLUE` no script de geração, que a usa para
  /// decidir quais pedaços de palavra hifenizada precisam entrar no filtro.
  static const _hyphenGlue = {
    'lo', 'la', 'los', 'las', 'no', 'na', 'nos', 'nas',
    'me', 'te', 'se', 'vos', 'lhe', 'lhes', 'o', 'a', 'os', 'as',
    'ei', 'ás', 'á', 'emos', 'eis', 'ão',
    'ia', 'ias', 'iam', 'íamos', 'íeis',
  };

  /// Percorre o texto e devolve as palavras desconhecidas, em ordem.
  List<Misspelling> check(String text) {
    if (text.isEmpty) return const [];
    final result = <Misspelling>[];
    for (final token in WordTokenizer.tokenize(text)) {
      if (isCorrect(token.text)) continue;
      result.add(
        Misspelling(
          start: token.start,
          length: token.text.length,
          word: token.text,
        ),
      );
    }
    return result;
  }

  bool isCorrect(String word) {
    // Letra solta é inicial de nome, marcador de lista ou artigo — nunca vale
    // a pena sublinhar.
    if (word.length < 2) return true;
    if (WordTokenizer.isAcronym(word)) return true;
    if (_lookup(word)) return true;
    if (word.contains('-')) return _isCompoundCorrect(word);
    return false;
  }

  /// Palavra composta vale quando **todos** os pedaços valem. Isso mantém o
  /// dicionário pequeno: as 7,8 milhões de formas hifenizadas do pt_BR não
  /// precisam estar no filtro.
  bool _isCompoundCorrect(String word) {
    final parts = word.split('-');
    for (final part in parts) {
      if (part.isEmpty) return false;
      if (part.length < 2) continue;
      if (WordTokenizer.isAcronym(part)) continue;
      if (_hyphenGlue.contains(WordTokenizer.normalize(part))) continue;
      if (!_lookup(part)) return false;
    }
    return true;
  }

  bool _lookup(String word) {
    final normalized = WordTokenizer.normalize(word);
    return _ignored.contains(normalized) ||
        userDictionary.contains(normalized) ||
        dictionary.contains(normalized);
  }

  /// Aceita ou recusa um candidato de sugestão.
  ///
  /// Diferente de [isCorrect] em dois pontos: candidato nunca passa só por ser
  /// curto ou parecer sigla (ele vem sempre em minúsculas), e o resultado do
  /// filtro ainda passa pelo modelo de plausibilidade, que derruba a invenção
  /// ocasional causada pelo falso positivo do Bloom.
  /// A sugestão pode vir composta por espaço, quando o erro foi juntar duas
  /// palavras ("casa verde"), e por hífen ("anti-herói"). Cada palavra tem de
  /// valer sozinha; dentro dela, os pedaços de ênclise valem colados.
  bool _acceptSuggestion(String candidate) {
    for (final word in candidate.split(' ')) {
      if (word.isEmpty) return false;
      if (!word.contains('-')) {
        if (!_acceptSuggestionWord(word)) return false;
        continue;
      }
      for (final part in word.split('-')) {
        if (part.isEmpty) return false;
        if (_hyphenGlue.contains(WordTokenizer.normalize(part))) continue;
        if (!_acceptSuggestionWord(part)) return false;
      }
    }
    return true;
  }

  bool _acceptSuggestionWord(String word) {
    final normalized = WordTokenizer.normalize(word);
    // Nome de personagem aprendido no projeto não tem por que parecer
    // possível no idioma: ele passa antes do modelo.
    if (_ignored.contains(normalized) ||
        userDictionary.contains(normalized)) {
      return true;
    }
    if (!dictionary.contains(normalized)) return false;
    return plausibility?.isPlausible(normalized) ?? true;
  }

  /// Correções propostas para uma palavra, da mais provável para a menos.
  List<String> suggest(String word, {int limit = 7}) =>
      _suggestions.suggest(word, limit: limit);

  void ignore(String word) => _ignored.add(WordTokenizer.normalize(word));

  Future<void> learn(String word) => userDictionary.add(word);
}
