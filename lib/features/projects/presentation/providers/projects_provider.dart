import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/project_service.dart';
import '../../../../shared/models/prosa_project.dart';

final projectServiceProvider = Provider((_) => ProjectService());

final localProjectsProvider = FutureProvider<List<ProsaProject>>((ref) async {
  final service = ref.read(projectServiceProvider);
  return service.listLocalProjects();
});

final activeProjectProvider = StateProvider<ProsaProject?>((ref) => null);
