import 'bloom_dictionary.dart';

/// Diz se uma sequência de letras é possível no idioma.
///
/// Guarda todos os 4-gramas que ocorrem nas palavras do dicionário. Palavra
/// real sempre passa — os 4-gramas saíram dela. Sequência aleatória quase
/// nunca passa: em português nenhuma palavra começa com "ç" nem tem "âa" no
/// meio.
///
/// Existe por causa de um efeito colateral do filtro de Bloom: o gerador de
/// sugestões faz milhares de consultas por palavra corrigida, e a essa altura
/// a taxa de erro de 1 em 10.000 do filtro já é suficiente para uma invenção
/// aparecer na lista — às vezes no topo. Este modelo derruba essas invenções
/// sem descartar nenhuma correção legítima.
///
/// Nunca é usado para decidir se uma palavra **do texto** está errada: ali o
/// dicionário manda sozinho, e sublinhar por causa de um modelo estatístico
/// seria justamente o falso alarme que a arquitetura toda evita.
class PlausibilityModel {
  static const _ngramSize = 4;

  final BloomDictionary _grams;

  const PlausibilityModel(this._grams);

  /// Espelho de `ngrams` em `scripts/build_dictionaries.py`: marcas de início
  /// e fim entram no n-grama, que é o que torna a borda da palavra
  /// verificável.
  static Iterable<String> ngramsOf(String word) {
    final padded = '^$word\$';
    if (padded.length < _ngramSize) return [padded];
    return [
      for (var i = 0; i <= padded.length - _ngramSize; i++)
        padded.substring(i, i + _ngramSize),
    ];
  }

  /// Candidato composto é avaliado pedaço por pedaço: hífen e espaço não
  /// existem no modelo, que foi montado só com palavras simples.
  bool isPlausible(String candidate) {
    for (final part in candidate.split(RegExp(r'[- ]'))) {
      if (part.isEmpty) continue;
      for (final gram in ngramsOf(part)) {
        if (!_grams.contains(gram)) return false;
      }
    }
    return true;
  }
}
