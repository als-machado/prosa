import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/export_config_store.dart';
import '../../data/export_service.dart';

final exportServiceProvider = Provider<ExportService>((ref) {
  return const ExportService();
});

final exportConfigStoreProvider = Provider<ExportConfigStore>((ref) {
  return const ExportConfigStore();
});
