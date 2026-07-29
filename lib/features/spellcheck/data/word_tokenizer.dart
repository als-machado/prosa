/// Uma palavra localizada no texto, com o deslocamento onde começa.
class WordToken {
  final String text;
  final int start;

  const WordToken(this.text, this.start);

  int get end => start + text.length;
}

/// Separa o texto corrido em palavras verificáveis.
class WordTokenizer {
  WordTokenizer._();

  /// Uma palavra começa e termina em letra, e pode ter apóstrofos e hífens
  /// no meio (`d'água`, `guarda-chuva`, `chamá-lo`, `don't`).
  ///
  /// Dígitos ficam de fora, então `covid19` vira só `covid`. O travessão
  /// (`—`) do diálogo não entra na classe: só o hífen simples.
  static final RegExp _pattern = RegExp(
    r"\p{L}(?:[\p{L}'’\-]*\p{L})?",
    unicode: true,
  );

  static Iterable<WordToken> tokenize(String text) =>
      _pattern.allMatches(text).map((m) => WordToken(m.group(0)!, m.start));

  /// Normalização usada tanto na consulta quanto na geração do dicionário
  /// (ver `normalize` em `scripts/build_dictionaries.py`): apóstrofo
  /// tipográfico vira o reto, e tudo em minúsculas.
  static String normalize(String word) =>
      word.replaceAll('’', "'").toLowerCase();

  /// Siglas e numerais romanos (`ONU`, `XIV`, `PDFs`) não são verificáveis:
  /// nenhum dicionário as tem, e sublinhá-las é só ruído.
  ///
  /// O `s` final minúsculo é tolerado para o plural de sigla.
  static bool isAcronym(String word) {
    final core = word.endsWith('s') ? word.substring(0, word.length - 1) : word;
    if (core.length < 2) return false;
    if (core.toUpperCase() != core) return false;
    // Precisa ter ao menos uma letra: "..." ou "'-'" não são siglas.
    return core.toLowerCase() != core;
  }
}
