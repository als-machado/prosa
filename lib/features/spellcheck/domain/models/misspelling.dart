/// Uma palavra não encontrada no dicionário, com a posição dentro do texto
/// do nó (em unidades de código UTF-16, a mesma base de índice que o delta
/// do AppFlowy usa).
class Misspelling {
  final int start;
  final int length;
  final String word;

  const Misspelling({
    required this.start,
    required this.length,
    required this.word,
  });

  int get end => start + length;

  bool contains(int offset) => offset >= start && offset <= end;

  @override
  bool operator ==(Object other) =>
      other is Misspelling &&
      other.start == start &&
      other.length == length &&
      other.word == word;

  @override
  int get hashCode => Object.hash(start, length, word);

  @override
  String toString() => 'Misspelling($word @ $start+$length)';
}
