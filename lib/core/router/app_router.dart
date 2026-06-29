import 'package:go_router/go_router.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/editor/presentation/screens/editor_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/git/presentation/screens/commit_tree_screen.dart';
import '../../features/git/presentation/screens/ssh_settings_screen.dart';
import '../../features/projects/presentation/screens/new_project_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, s) => const HomeScreen()),
    GoRoute(path: '/editor', builder: (_, s) => const EditorScreen()),
    GoRoute(path: '/settings', builder: (_, s) => const SettingsScreen()),
    GoRoute(path: '/settings/ssh', builder: (_, s) => const SshSettingsScreen()),
    GoRoute(path: '/commits', builder: (_, s) => const CommitTreeScreen()),
    GoRoute(path: '/new-project', builder: (_, s) => const NewProjectScreen()),
  ],
);
