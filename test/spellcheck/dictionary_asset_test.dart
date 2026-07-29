import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:prosa/features/spellcheck/data/bloom_dictionary.dart';
import 'package:prosa/features/spellcheck/data/plausibility_model.dart';
import 'package:prosa/features/spellcheck/domain/models/spell_language.dart';

/// Carrega os dicionários pelo mesmo caminho que o app usa em produção — o
/// `rootBundle` — e não pelo sistema de arquivos.
///
/// É o que pega o erro mais bobo e mais provável da feature: o asset existir
/// no disco mas não estar declarado em `pubspec.yaml`, caso em que a
/// verificação simplesmente não funcionaria no app empacotado.
Future<BloomDictionary> _load(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  return BloomDictionary.fromBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final language in SpellLanguage.all) {
    group('assets de ${language.code}', () {
      test('o dicionário está declarado e carrega', () async {
        final dictionary = await _load(language.assetPath);
        expect(dictionary.language, language.code);
        expect(dictionary.wordCount, greaterThan(100000));
      });

      test('o modelo de n-gramas está declarado e carrega', () async {
        final model = PlausibilityModel(await _load(language.ngramAssetPath));
        expect(model.isPlausible('casa'), isTrue);
      });
    });
  }

  test('o dicionário carregado pelo bundle responde certo', () async {
    final dictionary = await _load(SpellLanguage.ptBR.assetPath);
    expect(dictionary.contains('coração'), isTrue);
    expect(dictionary.contains('corasao'), isFalse);
  });
}
