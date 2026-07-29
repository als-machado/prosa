import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prosa/features/spellcheck/data/bloom_dictionary.dart';

/// Lê o asset direto do disco: `flutter test` roda com a raiz do pacote como
/// diretório de trabalho, e assim o teste não depende do rootBundle.
BloomDictionary _load(String language) {
  final file = File('assets/dictionaries/$language.bloom');
  if (!file.existsSync()) {
    fail('Dicionário ausente. Rode: python3 scripts/build_dictionaries.py');
  }
  return BloomDictionary.fromBytes(file.readAsBytesSync());
}

void main() {
  group('cabeçalho', () {
    test('lê idioma, contagem e parâmetros', () {
      final dictionary = _load('pt_BR');
      expect(dictionary.language, 'pt_BR');
      expect(dictionary.wordCount, greaterThan(2000000));
    });

    test('rejeita arquivo que não é dicionário', () {
      final lixo = Uint8List(128);
      expect(
        () => BloomDictionary.fromBytes(lixo),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejeita arquivo truncado', () {
      expect(
        () => BloomDictionary.fromBytes(Uint8List(8)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // Estes testes valem por muito mais do que parece: eles confirmam que o
  // MurmurHash3 do Dart bate com o do Python que gerou o arquivo. Se as duas
  // pontas divergirem, o dicionário inteiro vira ruído e é aqui que aparece.
  group('consulta pt_BR', () {
    late BloomDictionary dictionary;
    setUpAll(() => dictionary = _load('pt_BR'));

    test('reconhece palavras que vêm dos radicais', () {
      for (final word in ['tempo', 'homem', 'noite', 'mão', 'história']) {
        expect(dictionary.contains(word), isTrue, reason: word);
      }
    });

    test('reconhece formas geradas por afixo', () {
      // Nenhuma destas é radical no .dic: saem da conjugação e da flexão.
      for (final word in [
        'casa',
        'livro',
        'escrevêssemos',
        'correríamos',
        'proseando',
        'gata',
      ]) {
        expect(dictionary.contains(word), isTrue, reason: word);
      }
    });

    test('reconhece o pedaço que só existe na ênclise', () {
      // "chamá" não é palavra solta, mas precisa existir para validar
      // "chamá-lo".
      expect(dictionary.contains('chamá'), isTrue);
      expect(dictionary.contains('vendê'), isTrue);
    });

    test('recusa erros de digitação', () {
      for (final word in [
        'casaa',
        'livrro',
        'chapeu',
        'corasao',
        'entaum',
        'xyzzy',
      ]) {
        expect(dictionary.contains(word), isFalse, reason: word);
      }
    });

    test('palavra vazia não é palavra', () {
      expect(dictionary.contains(''), isFalse);
    });
  });

  group('consulta en_US', () {
    test('reconhece e recusa o básico', () {
      final dictionary = _load('en_US');
      expect(dictionary.language, 'en_US');
      expect(dictionary.contains('house'), isTrue);
      expect(dictionary.contains('running'), isTrue);
      expect(dictionary.contains('hosue'), isFalse);
    });
  });
}
