import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../projects/presentation/providers/projects_provider.dart';
import '../../../git/presentation/providers/git_api_provider.dart';
import '../../../git/data/git_api_service.dart';
import '../../../git/presentation/providers/git_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../../shared/models/prosa_project.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localProjects = ref.watch(localProjectsProvider);
    final remoteProjects = ref.watch(remoteProjectsProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;
    final hasGit = settings?.gitProvider != null && settings?.gitToken != null;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            children: [
              Text('Prosa',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text('Editor para escritores',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  textAlign: TextAlign.center),
              const SizedBox(height: 40),
              localProjects.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Erro: $e'),
                data: (list) => _LocalProjects(projects: list),
              ),
              const SizedBox(height: 24),
              if (hasGit) ...[
                const Divider(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Projetos remotos (${settings!.gitProvider!.name})',
                        style: Theme.of(context).textTheme.titleSmall),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: 'Atualizar',
                      onPressed: () => ref.invalidate(remoteProjectsProvider),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                remoteProjects.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text('Erro ao buscar repos remotos: $e'),
                  data: (list) => _RemoteProjects(repos: list),
                ),
              ] else
                OutlinedButton.icon(
                  icon: const Icon(Icons.cloud_outlined),
                  label: const Text('Configurar integração Git'),
                  onPressed: () => context.go('/settings'),
                ),
              const SizedBox(height: 24),
              Center(
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Novo projeto'),
                  onPressed: () => context.go('/new-project'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalProjects extends ConsumerWidget {
  final List<ProsaProject> projects;
  const _LocalProjects({required this.projects});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (projects.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Projetos locais', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ...projects.map((p) => _LocalProjectCard(project: p)),
      ],
    );
  }
}

class _LocalProjectCard extends ConsumerWidget {
  final ProsaProject project;
  const _LocalProjectCard({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.book_outlined),
        title: Text(project.title),
        subtitle: Text(project.author, style: Theme.of(context).textTheme.bodySmall),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: () {
          ref.read(activeProjectProvider.notifier).state = project;
          context.go('/editor');
        },
      ),
    );
  }
}

class _RemoteProjects extends ConsumerWidget {
  final List<RemoteRepo> repos;
  const _RemoteProjects({required this.repos});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (repos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('Nenhum repositório Prosa encontrado na conta.'),
      );
    }
    return Column(
      children: repos.map((r) => _RemoteRepoCard(repo: r)).toList(),
    );
  }
}

class _RemoteRepoCard extends ConsumerWidget {
  final RemoteRepo repo;
  const _RemoteRepoCard({required this.repo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.cloud_outlined),
        title: Text(repo.name),
        subtitle: repo.description.isNotEmpty
            ? Text(repo.description, style: Theme.of(context).textTheme.bodySmall)
            : null,
        trailing: const Icon(Icons.download_outlined, size: 18),
        onTap: () => _clone(context, ref),
      ),
    );
  }

  Future<void> _clone(BuildContext context, WidgetRef ref) async {
    final service = ref.read(projectServiceProvider);
    final git = ref.read(gitServiceProvider);
    final base = await service.defaultProjectsDir;
    final dest = '${base.path}/${repo.name}';
    await git.clone(repo.sshUrl, dest);
    final project = await service.loadProject(dest);
    if (project != null) {
      ref.read(activeProjectProvider.notifier).state = project;
      ref.invalidate(localProjectsProvider);
      if (context.mounted) context.go('/editor');
    }
  }
}
