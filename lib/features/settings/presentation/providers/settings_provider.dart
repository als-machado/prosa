import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/settings_service.dart';
import '../../domain/models/app_settings.dart';

final settingsServiceProvider = Provider((_) => SettingsService());

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final service = ref.read(settingsServiceProvider);
    return service.load();
  }

  Future<void> save(AppSettings settings) async {
    final service = ref.read(settingsServiceProvider);
    await service.save(settings);
    state = AsyncData(settings);
  }

  Future<void> toggleDarkMode() async {
    final current = state.valueOrNull;
    if (current == null) return;
    await save(current.copyWith(darkMode: !current.darkMode));
  }
}
