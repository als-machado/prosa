import 'package:flutter_test/flutter_test.dart';
import 'package:prosa/features/spellcheck/data/word_tokenizer.dart';

void main() {
  group('tokenize', () {
    test('devolve palavras com o deslocamento onde começam', () {
      final tokens = WordTokenizer.tokenize('Ela abriu a porta.').toList();
      expect(tokens.map((t) => t.text), ['Ela', 'abriu', 'a', 'porta']);
      expect(tokens.map((t) => t.start), [0, 4, 10, 12]);
      expect(tokens.last.end, 17);
    });

    test('mantém hífen e apóstrofo dentro da palavra', () {
      expect(
        WordTokenizer.tokenize("chamá-lo d'água guarda-chuva don't")
            .map((t) => t.text),
        ['chamá-lo', "d'água", 'guarda-chuva', "don't"],
      );
    });

    test('não engole o travessão do diálogo', () {
      expect(
        WordTokenizer.tokenize('— Vamos, disse ela.').map((t) => t.text),
        ['Vamos', 'disse', 'ela'],
      );
    });

    test('corta dígitos e pontuação', () {
      expect(
        WordTokenizer.tokenize('covid19, 42 anos; e-mail: a@b.com')
            .map((t) => t.text),
        ['covid', 'anos', 'e-mail', 'a', 'b', 'com'],
      );
    });

    test('acentos não quebram a palavra', () {
      expect(
        WordTokenizer.tokenize('coração ônibus água pôr').map((t) => t.text),
        ['coração', 'ônibus', 'água', 'pôr'],
      );
    });
  });

  group('normalize', () {
    test('minúsculas e apóstrofo tipográfico viram o reto', () {
      expect(WordTokenizer.normalize('D’Água'), "d'água");
      expect(WordTokenizer.normalize('CASA'), 'casa');
    });
  });

  group('isAcronym', () {
    test('reconhece siglas e numerais romanos', () {
      expect(WordTokenizer.isAcronym('ONU'), isTrue);
      expect(WordTokenizer.isAcronym('XIV'), isTrue);
      expect(WordTokenizer.isAcronym('PDFs'), isTrue);
    });

    test('palavra normal e letra solta não são sigla', () {
      expect(WordTokenizer.isAcronym('Casa'), isFalse);
      expect(WordTokenizer.isAcronym('casa'), isFalse);
      expect(WordTokenizer.isAcronym('A'), isFalse);
    });
  });
}
