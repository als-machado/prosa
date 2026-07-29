import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../projects/presentation/providers/projects_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/bloom_dictionary.dart';
import '../../data/plausibility_model.dart';
import '../../data/spell_checker.dart';
import '../../data/user_dictionary.dart';
import '../../domain/models/spell_language.dart';
import '../spellcheck_highlighter.dart';

/// Idioma efetivo da verificação: o escolhido nas configurações e, na falta
/// dele, o idioma do projeto (campo `language` do `.prosa`). Null quando a
/// verificação está desligada ou o idioma não tem dicionário.
final spellLanguageProvider = Provider<SpellLanguage?>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  if (settings == null || !settings.spellcheckEnabled) return null;
  final project = ref.watch(activeProjectProvider);
  return SpellLanguage.resolve(
    settings.spellcheckLanguage ?? project?.language,
  );
});

Future<BloomDictionary> _loadBloom(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  return BloomDictionary.fromBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

/// Carrega o filtro de Bloom do asset.
///
/// `keepAlive` porque são alguns megabytes por idioma: recarregar a cada
/// troca de arquivo ou de projeto seria desperdício, e o conteúdo nunca muda.
final bloomDictionaryProvider =
    FutureProvider.family<BloomDictionary, SpellLanguage>(
        (ref, language) async {
  ref.keepAlive();
  return _loadBloom(language.assetPath);
});

/// Modelo de 4-gramas do idioma, usado só para descartar sugestões
/// impossíveis. É pequeno (algumas centenas de KB).
final plausibilityModelProvider =
    FutureProvider.family<PlausibilityModel, SpellLanguage>(
        (ref, language) async {
  ref.keepAlive();
  return PlausibilityModel(await _loadBloom(language.ngramAssetPath));
});

/// Palavras aprendidas, lidas do arquivo versionado na raiz do projeto.
final userDictionaryProvider = FutureProvider<UserDictionary>((ref) async {
  final project = ref.watch(activeProjectProvider);
  return UserDictionary.load(
    project == null
        ? null
        : '${project.localPath}/${AppConstants.dictionaryFileName}',
  );
});

final spellCheckerProvider = FutureProvider<SpellChecker?>((ref) async {
  final language = ref.watch(spellLanguageProvider);
  if (language == null) return null;
  final dictionary = await ref.watch(bloomDictionaryProvider(language).future);
  final plausibility = await ref.watch(plausibilityModelProvider(language).future);
  final userDictionary = await ref.watch(userDictionaryProvider.future);
  return SpellChecker(
    dictionary: dictionary,
    language: language,
    userDictionary: userDictionary,
    plausibility: plausibility,
  );
});

/// Vive acima da tela do editor: guarda o cache por parágrafo e sobrevive à
/// troca de arquivo (o cache é limpo no `attach`).
final spellcheckHighlighterProvider = Provider<SpellcheckHighlighter>((ref) {
  final highlighter = SpellcheckHighlighter();
  ref.onDispose(highlighter.dispose);
  ref.listen<AsyncValue<SpellChecker?>>(
    spellCheckerProvider,
    (_, next) => highlighter.checker = next.valueOrNull,
    fireImmediately: true,
  );
  return highlighter;
});
