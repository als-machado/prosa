import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import '../../../features/projects/presentation/providers/projects_provider.dart';
import '../../../features/editor/presentation/providers/editor_provider.dart';
import '../../../features/git/presentation/providers/git_provider.dart';
import '../../../features/git/presentation/widgets/branch_dialog.dart';
import '../../../features/chapters/presentation/widgets/new_chapter_dialog.dart';
import '../../../features/chapters/presentation/widgets/new_scene_dialog.dart';
import '../../../features/characters/presentation/widgets/new_character_dialog.dart';
import '../../../core/constants/app_constants.dart';

class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(activeProjectProvider);
    final theme = Theme.of(context);
    final sidebarColor = theme.colorScheme.surfaceContainerLowest;
    final branch = ref.watch(currentBranchProvider);

    return Container(
      width: 260,
      color: sidebarColor,
      child: Column(
        children: [
          _SidebarHeader(projectTitle: project?.title ?? 'Prosa'),
          if (branch.valueOrNull != null)
            _BranchIndicator(branch: branch.valueOrNull!),
          const Divider(height: 1),
          if (project != null) ...[
            Expanded(
              child: _ProjectTree(projectPath: project.localPath),
            ),
          ] else
            const Expanded(child: Center(child: Text('Nenhum projeto aberto'))),
          const Divider(height: 1),
          _SidebarFooter(),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  final String projectTitle;
  const _SidebarHeader({required this.projectTitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              projectTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchIndicator extends StatelessWidget {
  final String branch;
  const _BranchIndicator({required this.branch});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.call_split, size: 14),
          const SizedBox(width: 6),
          Text(branch, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ProjectTree extends ConsumerWidget {
  final String projectPath;
  const _ProjectTree({required this.projectPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chaptersDir = Directory('$projectPath/${AppConstants.chaptersDir}');
    final charactersDir = Directory('$projectPath/${AppConstants.charactersDir}');
    final chapters = chaptersDir.existsSync()
        ? chaptersDir.listSync().whereType<Directory>().toList()
        : <Directory>[];
    final characters = charactersDir.existsSync()
        ? charactersDir.listSync().whereType<Directory>().toList()
        : <Directory>[];

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _SectionHeader(
          title: 'Capítulos',
          onAdd: () => _showNewChapterDialog(context, ref),
        ),
        ...chapters.map((d) => _ChapterTile(dir: d, ref: ref)),
        const SizedBox(height: 8),
        _SectionHeader(
          title: 'Personagens',
          onAdd: () => _showNewCharacterDialog(context, ref),
        ),
        ...characters.map((d) => _CharacterTile(dir: d, ref: ref)),
        const SizedBox(height: 8),
        _SectionHeader(title: 'Extras', onAdd: null),
        _MiscTile(
          label: 'Sinopse',
          path: '$projectPath/${AppConstants.miscDir}/${AppConstants.synopsisFile}',
          ref: ref,
        ),
        _MiscTile(
          label: 'Glossário',
          path: '$projectPath/${AppConstants.miscDir}/${AppConstants.glossaryFile}',
          ref: ref,
        ),
        _MiscTile(label: 'Notas', path: '$projectPath/${AppConstants.miscDir}/${AppConstants.notesDir}', ref: ref),
        _MiscTile(label: 'Locais', path: '$projectPath/${AppConstants.miscDir}/${AppConstants.locationsDir}', ref: ref),
        _MiscTile(label: 'Pesquisa', path: '$projectPath/${AppConstants.miscDir}/${AppConstants.researchDir}', ref: ref),
        _MiscTile(label: 'Linha do tempo', path: '$projectPath/${AppConstants.miscDir}/${AppConstants.timelineDir}', ref: ref),
        _MiscTile(label: 'Regras do mundo', path: '$projectPath/${AppConstants.miscDir}/${AppConstants.worldRulesDir}', ref: ref),
      ],
    );
  }

  Future<void> _showNewChapterDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => NewChapterDialog(projectPath: projectPath),
    );
    if (result != null) ref.invalidate(activeProjectProvider);
  }

  Future<void> _showNewCharacterDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => NewCharacterDialog(projectPath: projectPath),
    );
    if (result != null) ref.invalidate(activeProjectProvider);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onAdd;
  const _SectionHeader({required this.title, this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Text(title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2)),
          const Spacer(),
          if (onAdd != null)
            IconButton(
              icon: const Icon(Icons.add, size: 16),
              onPressed: onAdd,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}

class _ChapterTile extends ConsumerWidget {
  final Directory dir;
  final WidgetRef ref;
  const _ChapterTile({required this.dir, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = dir.path.split('/').last;
    final chapterFile = File('${dir.path}/${AppConstants.chapterFile}');
    final scenes = dir.listSync().whereType<File>()
        .where((f) => f.path.endsWith('.md') && !f.path.endsWith(AppConstants.chapterFile))
        .toList();
    final hasScenes = !chapterFile.existsSync() && scenes.isNotEmpty;

    if (!hasScenes) {
      return _SidebarTile(
        label: name,
        icon: Icons.article_outlined,
        onTap: () => _openFile(ref, context, chapterFile.path),
        indent: 1,
      );
    }

    return ExpansionTile(
      tilePadding: const EdgeInsets.only(left: 24, right: 8),
      title: Text(name, style: Theme.of(context).textTheme.bodySmall),
      leading: const Icon(Icons.menu_book_outlined, size: 16),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add, size: 14),
            tooltip: 'Nova cena',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => NewSceneDialog(chapterPath: dir.path, chapterName: name),
            ),
          ),
          const Icon(Icons.expand_more, size: 16),
        ],
      ),
      childrenPadding: EdgeInsets.zero,
      children: scenes.map((f) {
        final sceneName = f.path.split('/').last.replaceAll('.md', '');
        return _SidebarTile(
          label: sceneName,
          icon: Icons.short_text,
          onTap: () => _openFile(ref, context, f.path),
          indent: 2,
        );
      }).toList(),
    );
  }

  void _openFile(WidgetRef ref, BuildContext context, String path) {
    ref.read(activeFileProvider.notifier).state = path;
    context.go('/editor');
  }
}

class _CharacterTile extends ConsumerWidget {
  final Directory dir;
  final WidgetRef ref;
  const _CharacterTile({required this.dir, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = dir.path.split('/').last;
    return ExpansionTile(
      tilePadding: const EdgeInsets.only(left: 24, right: 8),
      title: Text(name, style: Theme.of(context).textTheme.bodySmall),
      leading: const Icon(Icons.person_outline, size: 16),
      childrenPadding: EdgeInsets.zero,
      children: [
        _SidebarTile(
          label: 'Características',
          icon: Icons.list_alt_outlined,
          onTap: () {
            ref.read(activeFileProvider.notifier).state = '${dir.path}/characteristics.md';
            context.go('/editor');
          },
          indent: 2,
        ),
        _SidebarTile(
          label: 'Evolução',
          icon: Icons.trending_up_outlined,
          onTap: () {
            ref.read(activeFileProvider.notifier).state = '${dir.path}/evolution.md';
            context.go('/editor');
          },
          indent: 2,
        ),
      ],
    );
  }
}

class _MiscTile extends ConsumerWidget {
  final String label;
  final String path;
  final WidgetRef ref;
  const _MiscTile({required this.label, required this.path, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SidebarTile(
      label: label,
      icon: Icons.folder_outlined,
      onTap: () {
        ref.read(activeFileProvider.notifier).state = path;
        context.go('/editor');
      },
      indent: 1,
    );
  }
}

class _SidebarTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final int indent;
  const _SidebarTile({required this.label, required this.icon, required this.onTap, this.indent = 1});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: 16.0 * indent, right: 8, top: 6, bottom: 6),
        child: Row(
          children: [
            Icon(icon, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarFooter extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.call_split, size: 18),
            tooltip: 'Branches',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const BranchDialog(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.commit, size: 18),
            tooltip: 'Commits',
            onPressed: () => context.push('/commits'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 18),
            tooltip: 'Configurações',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }
}
