/// Idiomas com dicionário disponível em `assets/dictionaries/`.
///
/// Para acrescentar um idioma: rodar
/// `python3 scripts/build_dictionaries.py --lang xx_YY` (a lista de idiomas
/// suportados pelo script vive lá) e adicionar a entrada aqui.
class SpellLanguage {
  /// Código do dicionário, igual ao nome do arquivo (`pt_BR`).
  final String code;

  /// Nome exibido na tela de configurações.
  final String label;

  /// Letras usadas para gerar candidatos de correção. Inclui as acentuadas:
  /// no português, trocar `a` por `á` é o erro mais comum de todos.
  final String alphabet;

  /// Grupos de letras que só diferem por acento/cedilha. Usados para propor
  /// "coracao" → "coração", que está a duas edições de distância e não
  /// apareceria na geração normal de candidatos.
  final List<String> diacriticGroups;

  /// Trocas de trecho que representam o mesmo som e concentram a maior parte
  /// dos erros de ortografia do idioma. Uma regra dessas resolve de uma vez o
  /// que exigiria três edições soltas: `recomendasao` → `recomendação`.
  final List<(String, String)> phoneticRules;

  const SpellLanguage({
    required this.code,
    required this.label,
    required this.alphabet,
    this.diacriticGroups = const [],
    this.phoneticRules = const [],
  });

  String get assetPath => 'assets/dictionaries/$code.bloom';

  /// Modelo de 4-gramas do idioma (ver PlausibilityModel).
  String get ngramAssetPath => 'assets/dictionaries/$code.ngram.bloom';

  static const ptBR = SpellLanguage(
    code: 'pt_BR',
    label: 'Português (Brasil)',
    alphabet: "abcdefghijklmnopqrstuvwxyzáàâãéêíóôõúüç'",
    diacriticGroups: ['aáàâã', 'eéê', 'ií', 'oóôõ', 'uúü', 'cç'],
    phoneticRules: [
      // Nasais escritas "de ouvido".
      ('sao', 'ção'), ('soes', 'ções'), ('coes', 'ções'), ('aum', 'ão'),
      ('am', 'ão'), ('ao', 'ão'), ('oe', 'õe'), ('ma', 'mã'),
      // Sibilantes: onde mora a maior parte dos erros do português.
      ('s', 'ç'), ('ss', 'ç'), ('c', 'ç'), ('ç', 'ss'), ('ç', 's'),
      ('s', 'ss'), ('ss', 's'), ('z', 's'), ('s', 'z'), ('x', 'ss'),
      ('z', 'ç'), ('c', 'ss'), ('ss', 'c'), ('sc', 'c'), ('c', 'sc'),
      // Outras confusões clássicas.
      ('x', 'ch'), ('ch', 'x'), ('j', 'g'), ('g', 'j'),
      ('li', 'lh'), ('ni', 'nh'), ('u', 'l'), ('l', 'u'),
      ('esa', 'eza'), ('eza', 'esa'), ('izar', 'isar'), ('isar', 'izar'),
    ],
  );

  static const enUS = SpellLanguage(
    code: 'en_US',
    label: 'Inglês (EUA)',
    alphabet: "abcdefghijklmnopqrstuvwxyz'",
    diacriticGroups: ['eé', 'aá', 'oó', 'uü', 'cç', 'nñ'],
    phoneticRules: [
      ('ie', 'ei'), ('ei', 'ie'), ('ph', 'f'), ('f', 'ph'),
      ('k', 'c'), ('c', 'k'), ('s', 'c'), ('c', 's'),
      ('able', 'ible'), ('ible', 'able'), ('ance', 'ence'), ('ence', 'ance'),
      ('shun', 'tion'), ('sion', 'tion'), ('tion', 'sion'),
    ],
  );

  static const all = [ptBR, enUS];

  /// Resolve o código de idioma do projeto (campo `language` do `.prosa`,
  /// no formato `pt-BR`) ou o escolhido nas configurações.
  ///
  /// A comparação cai para a subtag primária quando a variante exata não
  /// existe: `pt-PT` usa o dicionário do Brasil, que depois do Acordo
  /// Ortográfico erra pouco, e é bem melhor do que ficar sem verificação.
  /// Idioma desconhecido devolve null — aí a verificação fica desligada.
  /// Identidade pelo código: o provider de dicionário é uma `family` que usa
  /// o idioma como chave, e chave sem `==` recarregaria o asset à toa.
  @override
  bool operator ==(Object other) =>
      other is SpellLanguage && other.code == code;

  @override
  int get hashCode => code.hashCode;

  static SpellLanguage? resolve(String? languageCode) {
    if (languageCode == null || languageCode.isEmpty) return null;
    final normalized = languageCode.replaceAll('-', '_').toLowerCase();
    for (final language in all) {
      if (language.code.toLowerCase() == normalized) return language;
    }
    final primary = normalized.split('_').first;
    for (final language in all) {
      if (language.code.toLowerCase().split('_').first == primary) {
        return language;
      }
    }
    return null;
  }
}
