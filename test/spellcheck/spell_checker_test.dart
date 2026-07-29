import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prosa/features/spellcheck/data/bloom_dictionary.dart';
import 'package:prosa/features/spellcheck/data/plausibility_model.dart';
import 'package:prosa/features/spellcheck/data/spell_checker.dart';
import 'package:prosa/features/spellcheck/data/user_dictionary.dart';
import 'package:prosa/features/spellcheck/domain/models/spell_language.dart';

BloomDictionary _bloom(String name) {
  final file = File('assets/dictionaries/$name.bloom');
  if (!file.existsSync()) {
    fail('Dicionário ausente. Rode: python3 scripts/build_dictionaries.py');
  }
  return BloomDictionary.fromBytes(file.readAsBytesSync());
}

/// Corretor sem projeto aberto: o dicionário do usuário fica só em memória.
SpellChecker _checker(SpellLanguage language) => SpellChecker(
      dictionary: _bloom(language.code),
      language: language,
      userDictionary: UserDictionary(),
      plausibility: PlausibilityModel(_bloom('${language.code}.ngram')),
    );

void main() {
  group('check (pt_BR)', () {
    late SpellChecker checker;
    setUpAll(() => checker = _checker(SpellLanguage.ptBR));

    test('não sinaliza nada num parágrafo correto', () {
      const texto = 'Ela abriu a porta do quarto e sussurrou algo que ele não '
          'conseguiu entender.';
      expect(checker.check(texto), isEmpty);
    });

    test('sinaliza a palavra errada com posição e tamanho', () {
      const texto = 'Ela abriu a porta e sussurou algo.';
      final erros = checker.check(texto);
      expect(erros, hasLength(1));
      expect(erros.single.word, 'sussurou');
      expect(erros.single.start, texto.indexOf('sussurou'));
      expect(erros.single.length, 'sussurou'.length);
    });

    test('aceita maiúscula inicial e caixa alta', () {
      expect(checker.isCorrect('Casa'), isTrue);
      expect(checker.isCorrect('CASA'), isTrue);
    });

    test('aceita ênclise e mesóclise', () {
      for (final palavra in ['chamá-lo', 'diz-se', 'dar-te-ei', 'vendê-la']) {
        expect(checker.isCorrect(palavra), isTrue, reason: palavra);
      }
    });

    test('aceita palavra composta e recusa se um pedaço estiver errado', () {
      expect(checker.isCorrect('guarda-chuva'), isTrue);
      expect(checker.isCorrect('pé-de-moleque'), isTrue);
      expect(checker.isCorrect('guarda-xuva'), isFalse);
    });

    test('ignora sigla, numeral romano e letra solta', () {
      for (final palavra in ['ONU', 'XIV', 'PDFs', 'A']) {
        expect(checker.isCorrect(palavra), isTrue, reason: palavra);
      }
    });

    test('o travessão do diálogo não vira palavra', () {
      expect(checker.check('— Vamos, disse ela.'), isEmpty);
    });

    test('erros de ortografia comuns são pegos', () {
      for (final palavra in [
        'chapeu',
        'corasao',
        'atravez',
        'tambem',
        'voce',
        'nescessario',
      ]) {
        expect(checker.isCorrect(palavra), isFalse, reason: palavra);
      }
    });
  });

  group('dicionário do usuário e ignorar', () {
    test('palavra aprendida deixa de ser sinalizada', () async {
      final checker = _checker(SpellLanguage.ptBR);
      expect(checker.isCorrect('Zaphira'), isFalse);
      await checker.learn('Zaphira');
      expect(checker.isCorrect('Zaphira'), isTrue);
      // Vale independente da caixa em que for digitada depois.
      expect(checker.isCorrect('zaphira'), isTrue);
    });

    test('ignorar vale para a sessão', () {
      final checker = _checker(SpellLanguage.ptBR);
      expect(checker.isCorrect('Vhalgor'), isFalse);
      checker.ignore('Vhalgor');
      expect(checker.isCorrect('Vhalgor'), isTrue);
    });

    test('palavra aprendida também pode ser sugerida', () async {
      final checker = _checker(SpellLanguage.ptBR);
      await checker.learn('Zaphira');
      expect(checker.suggest('Zaphir', limit: 20), contains('Zaphira'));
    });
  });

  group('suggest (pt_BR)', () {
    late SpellChecker checker;
    setUpAll(() => checker = _checker(SpellLanguage.ptBR));

    test('a correção certa vem em primeiro lugar', () {
      const casos = {
        'chapeu': 'chapéu',
        'corasao': 'coração',
        'casaa': 'casa',
        'sussurou': 'sussurrou',
        'entaum': 'então',
        'recomendasao': 'recomendação',
        'atravez': 'através',
        'anti-heroi': 'anti-herói',
        'pricipalmente': 'principalmente',
        'orgao': 'órgão',
        'tambem': 'também',
        'voce': 'você',
        'pesoa': 'pessoa',
        'exersicio': 'exercício',
        'nescessario': 'necessário',
        'carrocel': 'carrossel',
        'cabeza': 'cabeça',
        'menssagem': 'mensagem',
        'maravilhozo': 'maravilhoso',
        'abitual': 'habitual',
        'guarda-xuva': 'guarda-chuva',
      };
      for (final caso in casos.entries) {
        final sugestoes = checker.suggest(caso.key);
        expect(
          sugestoes.isEmpty ? null : sugestoes.first,
          caso.value,
          reason: '${caso.key} -> $sugestoes',
        );
      }
    });

    test('espaço esquecido é proposto como duas palavras', () {
      expect(checker.suggest('casaverde').first, 'casa verde');
    });

    test('mantém a caixa da palavra original', () {
      expect(checker.suggest('Chapeu').first, 'Chapéu');
      expect(checker.suggest('CHAPEU').first, 'CHAPÉU');
    });

    test('não propõe sequência impossível no idioma', () {
      // O modelo de 4-gramas existe por causa disto: sem ele, o falso
      // positivo do filtro aparecia como "çázáverde" e "sucuróu".
      for (final palavra in ['casaverde', 'sussurou', 'atravez']) {
        for (final sugestao in checker.suggest(palavra)) {
          expect(sugestao.startsWith('ç'), isFalse, reason: sugestao);
          expect(sugestao, isNot(contains('âa')), reason: sugestao);
        }
      }
    });

    test('palavra curta não gera sugestão', () {
      expect(checker.suggest('a'), isEmpty);
    });
  });

  group('suggest (en_US)', () {
    test('a correção certa vem em primeiro lugar', () {
      final checker = _checker(SpellLanguage.enUS);
      const casos = {
        'hosue': 'house',
        'teh': 'the',
        'recieve': 'receive',
        'definately': 'definitely',
        'seperate': 'separate',
        'occured': 'occurred',
      };
      for (final caso in casos.entries) {
        final sugestoes = checker.suggest(caso.key);
        expect(
          sugestoes.isEmpty ? null : sugestoes.first,
          caso.value,
          reason: '${caso.key} -> $sugestoes',
        );
      }
    });
  });

  group('plausibilidade', () {
    test('palavra real passa, sequência impossível não', () {
      final model = PlausibilityModel(_bloom('pt_BR.ngram'));
      for (final palavra in ['casa', 'coração', 'sussurrou', 'guarda-chuva']) {
        expect(model.isPlausible(palavra), isTrue, reason: palavra);
      }
      for (final invencao in ['çázáverde', 'sucuróu', 'atrâavez']) {
        expect(model.isPlausible(invencao), isFalse, reason: invencao);
      }
    });
  });
}
