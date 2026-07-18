import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../features/projects/presentation/providers/projects_provider.dart';
import '../../../features/projects/presentation/providers/project_tree_provider.dart';
import '../../../features/editor/presentation/providers/editor_provider.dart';
import '../../../features/git/presentation/providers/git_provider.dart';
import '../../../features/git/presentation/widgets/branch_dialog.dart';
import '../../../features/chapters/presentation/widgets/new_chapter_dialog.dart';
import '../../../features/chapters/presentation/widgets/new_scene_dialog.dart';
import '../../../features/characters/presentation/widgets/new_character_dialog.dart';
import '../../../features/misc/presentation/widgets/new_markdown_file_dialog.dart';
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
    // Branch vazia = detached HEAD (checkout de um commit do histórico).
    // Sem aviso e sem caminho de volta, o escritor fica preso fora da branch.
    final detached = branch.isEmpty;
    final theme = Theme.of(context);
    final color = detached ? theme.colorScheme.error : null;

    return InkWell(
      onTap: () => showDialog(
        context: context,
        builder: (_) => const BranchDialog(),
      ),
      child: Tooltip(
        message: detached
            ? 'Você está em um commit do histórico, fora de qualquer branch. Clique para voltar a uma branch.'
            : 'Gerenciar branches',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Icon(detached ? Icons.warning_amber : Icons.call_split, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  detached ? 'Fora de branch — clique para voltar' : branch,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectTree extends ConsumerWidget {
  final String projectPath;
  const _ProjectTree({required this.projectPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(projectTreeProvider(projectPath));
    final chapters = tree.valueOrNull?.chapters ?? const <ChapterNode>[];
    final characters = tree.valueOrNull?.characters ?? const <CharacterNode>[];
    final miscSections = tree.valueOrNull?.miscSections ?? const <MiscSection>[];

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _SectionHeader(
          title: 'Capítulos',
          onAdd: () => _showNewChapterDialog(context, ref),
        ),
        ...chapters.map((c) => _ChapterTile(chapter: c)),
        const SizedBox(height: 8),
        _SectionHeader(
          title: 'Personagens',
          onAdd: () => _showNewCharacterDialog(context, ref),
        ),
        ...characters.map((c) => _CharacterTile(character: c)),
        const SizedBox(height: 8),
        _SectionHeader(title: 'Extras', onAdd: null),
        _SidebarTile(
          label: 'Sinopse',
          icon: Icons.description_outlined,
          path: '$projectPath/${AppConstants.miscDir}/${AppConstants.synopsisFile}',
        ),
        _SidebarTile(
          label: 'Glossário',
          icon: Icons.description_outlined,
          path: '$projectPath/${AppConstants.miscDir}/${AppConstants.glossaryFile}',
        ),
        ...miscSections.map((s) => _MiscSectionTile(section: s)),
      ],
    );
  }

  Future<void> _showNewChapterDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => NewChapterDialog(projectPath: projectPath),
    );
    // invalidar activeProjectProvider aqui resetaria o StateProvider para
    // null e fecharia o projeto — o que se quer é recarregar a árvore.
    if (result != null) ref.invalidate(projectTreeProvider(projectPath));
  }

  Future<void> _showNewCharacterDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => NewCharacterDialog(projectPath: projectPath),
    );
    if (result != null) ref.invalidate(projectTreeProvider(projectPath));
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
  final ChapterNode chapter;
  const _ChapterTile({required this.chapter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!chapter.hasScenes) {
      return _SidebarTile(
        label: chapter.name,
        icon: Icons.article_outlined,
        path: chapter.chapterFilePath,
        indent: 1,
      );
    }

    return ExpansionTile(
      tilePadding: const EdgeInsets.only(left: 24, right: 8),
      title: Text(chapter.name, style: Theme.of(context).textTheme.bodySmall),
      leading: const Icon(Icons.menu_book_outlined, size: 16),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add, size: 14),
            tooltip: 'Nova cena',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _showNewSceneDialog(context, ref),
          ),
          const Icon(Icons.expand_more, size: 16),
        ],
      ),
      childrenPadding: EdgeInsets.zero,
      children: chapter.scenes.map((scene) {
        return _SidebarTile(
          label: scene.name,
          icon: Icons.short_text,
          path: scene.path,
          indent: 2,
        );
      }).toList(),
    );
  }

  Future<void> _showNewSceneDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => NewSceneDialog(chapterPath: chapter.dirPath, chapterName: chapter.name),
    );
    if (result != null) ref.invalidate(projectTreeProvider);
  }
}

class _CharacterTile extends ConsumerWidget {
  final CharacterNode character;
  const _CharacterTile({required this.character});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.only(left: 24, right: 8),
      title: Text(character.name, style: Theme.of(context).textTheme.bodySmall),
      leading: const Icon(Icons.person_outline, size: 16),
      childrenPadding: EdgeInsets.zero,
      children: [
        _SidebarTile(
          label: 'Características',
          icon: Icons.list_alt_outlined,
          path: '${character.dirPath}/${AppConstants.characteristicsFile}',
          indent: 2,
        ),
        _SidebarTile(
          label: 'Evolução',
          icon: Icons.trending_up_outlined,
          path: '${character.dirPath}/${AppConstants.evolutionFile}',
          indent: 2,
        ),
      ],
    );
  }
}

class _MiscSectionTile extends ConsumerWidget {
  final MiscSection section;
  const _MiscSectionTile({required this.section});

  static const _labels = {
    AppConstants.notesDir: 'Notas',
    AppConstants.locationsDir: 'Locais',
    AppConstants.researchDir: 'Pesquisa',
    AppConstants.timelineDir: 'Linha do tempo',
    AppConstants.worldRulesDir: 'Regras do mundo',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = _labels[section.dirName] ?? section.dirName;
    return ExpansionTile(
      tilePadding: const EdgeInsets.only(left: 24, right: 8),
      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
      leading: const Icon(Icons.folder_outlined, size: 16),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add, size: 14),
            tooltip: 'Novo item',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _showNewFileDialog(context, ref, label),
          ),
          const Icon(Icons.expand_more, size: 16),
        ],
      ),
      childrenPadding: EdgeInsets.zero,
      children: section.files.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 4, bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Vazio — use o + para criar',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          )),
                ),
              ),
            ]
          : section.files
              .map((f) => _SidebarTile(
                    label: f.name,
                    icon: Icons.short_text,
                    path: f.path,
                    indent: 2,
                  ))
              .toList(),
    );
  }

  Future<void> _showNewFileDialog(BuildContext context, WidgetRef ref, String label) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => NewMarkdownFileDialog(dirPath: section.dirPath, sectionLabel: label),
    );
    if (result != null) ref.invalidate(projectTreeProvider);
  }
}

class _SidebarTile extends ConsumerWidget {
  final String label;
  final IconData icon;
  final String path;
  final int indent;
  const _SidebarTile({required this.label, required this.icon, required this.path, this.indent = 1});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = ref.watch(activeFileProvider) == path;
    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = Theme.of(context).textTheme.bodySmall;

    return Material(
      color: isActive ? colorScheme.primary.withValues(alpha: 0.10) : Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(activeFileProvider.notifier).state = path;
          context.go('/editor');
        },
        child: Padding(
          padding: EdgeInsets.only(left: 16.0 * indent, right: 8, top: 6, bottom: 6),
          child: Row(
            children: [
              Icon(icon, size: 14, color: isActive ? colorScheme.primary : null),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: isActive
                      ? baseStyle?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w600)
                      : baseStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
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
            icon: const Icon(Icons.home_outlined, size: 18),
            tooltip: 'Trocar de projeto',
            onPressed: () => context.go('/'),
          ),
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
