import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/git_api_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

final gitApiServiceProvider = Provider((_) => GitApiService());

final remoteProjectsProvider = FutureProvider<List<RemoteRepo>>((ref) async {
  final settings = await ref.watch(settingsProvider.future);
  if (settings.gitProvider == null || settings.gitToken == null) return [];
  final api = ref.read(gitApiServiceProvider);
  return api.listProsaRepos(settings);
});
