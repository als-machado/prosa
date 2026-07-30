import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/models/prosa_project.dart';
import '../../../projects/presentation/providers/project_tree_provider.dart';
import '../../data/export_config_store.dart';
import '../../data/export_service.dart';
import '../../data/image_loader.dart';
import '../../domain/models/book_metadata.dart';
import '../../domain/models/export_format.dart';
import '../../domain/models/export_selection.dart';
import '../providers/export_provider.dart';

/// Escolhe formato, conteúdo, metadados e capa, e escreve o arquivo.
///
/// A árvore do projeto e a configuração guardada chegam prontas: quem abre o
/// diálogo já leu o disco. Assim a tela não precisa de estado de carregamento
/// e continua sendo só interface.
class ExportDialog extends ConsumerStatefulWidget {
  final ProsaProject project;
  final ProjectTree tree;
  final ExportConfig config;

  const ExportDialog({
    super.key,
    required this.project,
    required this.tree,
    required this.config,
  });

  @override
  ConsumerState<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<ExportDialog> {
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _language = TextEditingController();
  final _publisher = TextEditingController();
  final _isbn = TextEditingController();
  final _description = TextEditingController();
  final _rights = TextEditingController();
  final _subjects = TextEditingController();
  final _publishedAt = TextEditingController();

  late ExportFormat _format = widget.config.format;
  late ExportSelection _selection = widget.config.selection;
  late String? _coverPath = widget.config.coverPath;
  Uint8List? _coverPreview;

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    final metadata = widget.config.metadata;
    _title.text = metadata.title;
    _author.text = metadata.author;
    _language.text = metadata.language;
    _publisher.text = metadata.publisher;
    _isbn.text = metadata.isbn;
    _description.text = metadata.description;
    _rights.text = metadata.rights;
    _subjects.text = metadata.subjects.join(', ');
    _publishedAt.text = metadata.publishedAt == null
        ? ''
        : metadata.publishedAt!.toIso8601String().split('T').first;

    final coverPath = _coverPath;
    if (coverPath != null) _loadCoverPreview(coverPath);
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _author,
      _language,
      _publisher,
      _isbn,
      _description,
      _rights,
      _subjects,
      _publishedAt,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCoverPreview(String path) async {
    try {
      final image = await loadExportImage(path);
      if (mounted) setState(() => _coverPreview = image.bytes);
    } catch (_) {
      // Capa apagada ou movida desde a última exportação: some da tela e o
      // autor escolhe outra. O erro só aparece se ele tentar exportar assim.
      if (mounted) setState(() => _coverPreview = null);
    }
  }

  ExportConfig _currentConfig() {
    return widget.config.copyWith(
      format: _format,
      selection: _selection,
      coverPath: _coverPath,
      clearCover: _coverPath == null,
      metadata: BookMetadata(
        title: _title.text.trim(),
        author: _author.text.trim(),
        language: _language.text.trim().isEmpty ? 'pt-BR' : _language.text.trim(),
        publisher: _publisher.text.trim(),
        description: _description.text.trim(),
        rights: _rights.text.trim(),
        isbn: _isbn.text.trim(),
        subjects: _subjects.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        publishedAt: DateTime.tryParse(_publishedAt.text.trim()),
      ),
    );
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      final config = _currentConfig();
      final result = await ref.read(exportServiceProvider).export(
            project: widget.project,
            tree: widget.tree,
            config: config,
          );

      final path = await _chooseDestination(result);
      if (path == null) {
        setState(() => _busy = false);
        return;
      }

      final file = File(path);
      // O seletor de arquivos de algumas plataformas já grava os bytes;
      // só escrevemos quando ele não gravou.
      if (!await file.exists() || await file.length() != result.bytes.length) {
        await file.writeAsBytes(result.bytes);
      }

      await ref
          .read(exportConfigStoreProvider)
          .save(widget.project, config, widget.tree);

      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('Livro exportado em $path')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _busy = false;
      });
    }
  }

  Future<String?> _chooseDestination(ExportResult result) async {
    String? chosen;
    try {
      chosen = await FilePicker.platform.saveFile(
        dialogTitle: 'Salvar livro exportado',
        fileName: result.fileName,
        initialDirectory: widget.project.localPath,
        bytes: result.bytes,
      );
    } catch (_) {
      // Sem seletor de arquivos do sistema (sessão sem portal XDG, por
      // exemplo) a exportação não pode simplesmente morrer: o arquivo vai
      // para dentro do projeto e o caminho aparece no aviso.
      final dir = Directory('${widget.project.localPath}/export');
      await dir.create(recursive: true);
      return '${dir.path}/${result.fileName}';
    }

    if (chosen == null) return null;
    final suffix = '.${_format.extension}';
    return chosen.toLowerCase().endsWith(suffix) ? chosen : '$chosen$suffix';
  }

  Future<void> _pickCover() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'Escolher imagem de capa',
        type: FileType.image,
      );
      final path = picked?.files.single.path;
      if (path == null) return;

      final image = await loadExportImage(path);
      if (!mounted) return;
      setState(() {
        _coverPath = path;
        _coverPreview = image.bytes;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(780.0, screen.width - 48);
    final height = math.min(640.0, screen.height - 96);

    return Dialog(
      child: SizedBox(
        width: width,
        height: height,
        child: DefaultTabController(
          length: 3,
          child: Column(
            children: [
              _header(),
              const TabBar(
                tabs: [
                  Tab(text: 'Conteúdo'),
                  Tab(text: 'Metadados'),
                  Tab(text: 'Capa'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _ContentTab(
                      tree: widget.tree,
                      selection: _selection,
                      onChanged: (s) => setState(() => _selection = s),
                    ),
                    _metadataTab(),
                    _coverTab(),
                  ],
                ),
              ),
              const Divider(height: 1),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Exportar livro',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          SizedBox(
            width: 300,
            child: DropdownButtonFormField<ExportFormat>(
              initialValue: _format,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Formato',
                helperText: _format.description,
                helperMaxLines: 2,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              items: ExportFormat.values.map((format) {
                final available = ExportService.isAvailable(format);
                return DropdownMenuItem(
                  value: format,
                  enabled: available,
                  child: Text(
                    available ? format.label : '${format.label} — em breve',
                    style: available
                        ? null
                        : TextStyle(color: Theme.of(context).disabledColor),
                  ),
                );
              }).toList(),
              onChanged: _busy
                  ? null
                  : (format) {
                      if (format != null) setState(() => _format = format);
                    },
            ),
          ),
        ],
      ),
    );
  }

  Widget _metadataTab() {
    if (!_format.supportsMetadata) {
      return _Placeholder(
        icon: Icons.info_outline,
        message: 'O formato ${_format.label} não guarda metadados no arquivo.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _field(_title, 'Título'),
        const SizedBox(height: 12),
        _field(_author, 'Autor'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _field(
                _language,
                'Idioma',
                helper: 'Código do idioma: pt-BR, pt-PT, en-US…',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _field(_publisher, 'Editora')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _field(
                _isbn,
                'ISBN',
                helper: 'Sem ISBN, o livro é identificado por um código interno.',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _field(
                _publishedAt,
                'Data de publicação',
                hint: 'AAAA-MM-DD',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _field(
          _subjects,
          'Gêneros',
          helper: 'Separados por vírgula: fantasia, aventura',
        ),
        const SizedBox(height: 12),
        _field(_description, 'Descrição', maxLines: 4),
        const SizedBox(height: 12),
        _field(_rights, 'Direitos autorais'),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? helper,
    String? hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      enabled: !_busy,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        hintText: hint,
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }

  Widget _coverTab() {
    if (!_format.supportsCover) {
      return _Placeholder(
        icon: Icons.info_outline,
        message: 'O formato ${_format.label} não tem capa.',
      );
    }

    final theme = Theme.of(context);
    final preview = _coverPreview;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Center(
              child: preview == null
                  ? _Placeholder(
                      icon: Icons.image_outlined,
                      message: 'Sem capa.\nO livro sai com a página de rosto.',
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(preview, fit: BoxFit.contain),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (_coverPath != null)
            Text(
              _coverPath!,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _pickCover,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Escolher imagem…'),
              ),
              const SizedBox(width: 8),
              if (_coverPath != null)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _coverPath = null;
                            _coverPreview = null;
                          }),
                  child: const Text('Remover'),
                ),
              const Spacer(),
              Flexible(
                child: Text(
                  'JPEG, PNG ou GIF. Proporção 2:3 (ex.: 1600×2400).',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    final theme = Theme.of(context);
    final chapters = _selection.chapters.length;
    final appendices = _selection.characters.length +
        _selection.miscFiles.length +
        (_selection.synopsis ? 1 : 0) +
        (_selection.glossary ? 1 : 0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: _error != null
                ? Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                  )
                : Text(
                    '$chapters ${chapters == 1 ? 'capítulo' : 'capítulos'}'
                    '${appendices == 0 ? '' : ', $appendices ${appendices == 1 ? 'apêndice' : 'apêndices'}'}',
                    style: theme.textTheme.bodySmall,
                  ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: (_busy || _selection.isEmpty) ? null : _export,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Exportar'),
          ),
        ],
      ),
    );
  }
}

class _ContentTab extends StatelessWidget {
  final ProjectTree tree;
  final ExportSelection selection;
  final ValueChanged<ExportSelection> onChanged;

  const _ContentTab({
    required this.tree,
    required this.selection,
    required this.onChanged,
  });

  static const _miscLabels = {
    AppConstants.notesDir: 'Notas',
    AppConstants.locationsDir: 'Locais',
    AppConstants.researchDir: 'Pesquisa',
    AppConstants.timelineDir: 'Linha do tempo',
    AppConstants.worldRulesDir: 'Regras do mundo',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _SelectableGroup(
          title: 'Capítulos',
          initiallyExpanded: true,
          items: tree.chapters
              .map(
                (chapter) => _GroupItem(
                  key: chapter.dirPath,
                  label: chapter.name,
                  subtitle: chapter.hasScenes
                      ? '${chapter.scenes.length} '
                          '${chapter.scenes.length == 1 ? 'cena' : 'cenas'}'
                      : null,
                ),
              )
              .toList(),
          selected: selection.chapters,
          onChanged: (keys) => onChanged(selection.copyWith(chapters: keys)),
          emptyHint: 'Este projeto ainda não tem capítulos.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'APÊNDICES',
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Entram no fim do livro, depois do último capítulo.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
        CheckboxListTile(
          dense: true,
          value: selection.synopsis,
          title: const Text('Sinopse'),
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) => onChanged(selection.copyWith(synopsis: v ?? false)),
        ),
        CheckboxListTile(
          dense: true,
          value: selection.glossary,
          title: const Text('Glossário'),
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) => onChanged(selection.copyWith(glossary: v ?? false)),
        ),
        _SelectableGroup(
          title: 'Personagens',
          items: tree.characters
              .map((c) => _GroupItem(key: c.dirPath, label: c.name))
              .toList(),
          selected: selection.characters,
          onChanged: (keys) => onChanged(selection.copyWith(characters: keys)),
        ),
        ...tree.miscSections.map(
          (section) => _SelectableGroup(
            title: _miscLabels[section.dirName] ?? section.dirName,
            items: section.files
                .map((f) => _GroupItem(key: f.path, label: f.name))
                .toList(),
            selected: selection.miscFiles,
            onChanged: (keys) {
              // Cada grupo mexe só nos próprios arquivos; o conjunto guardado
              // é um só para todas as pastas de misc/.
              final own = section.files.map((f) => f.path).toSet();
              onChanged(
                selection.copyWith(
                  miscFiles: {
                    ...selection.miscFiles.where((p) => !own.contains(p)),
                    ...keys.where(own.contains),
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GroupItem {
  final String key;
  final String label;
  final String? subtitle;
  const _GroupItem({required this.key, required this.label, this.subtitle});
}

/// Grupo de itens com uma caixa "todos" no cabeçalho, em três estados.
class _SelectableGroup extends StatelessWidget {
  final String title;
  final List<_GroupItem> items;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool initiallyExpanded;
  final String? emptyHint;

  const _SelectableGroup({
    required this.title,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.initiallyExpanded = false,
    this.emptyHint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keys = items.map((i) => i.key).toSet();
    final chosen = keys.intersection(selected);
    final all = keys.isNotEmpty && chosen.length == keys.length;
    final none = chosen.isEmpty;

    if (items.isEmpty && emptyHint == null) return const SizedBox.shrink();

    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      tilePadding: const EdgeInsets.only(left: 8, right: 16),
      leading: Checkbox(
        tristate: true,
        value: all ? true : (none ? false : null),
        onChanged: items.isEmpty
            ? null
            : (_) => onChanged(
                  all
                      ? selected.difference(keys)
                      : {...selected, ...keys},
                ),
      ),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: items.isEmpty
          ? null
          : Text('${chosen.length} de ${items.length}',
              style: theme.textTheme.bodySmall),
      childrenPadding: const EdgeInsets.only(left: 16),
      children: items.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    emptyHint ?? 'Vazio',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              ),
            ]
          : items
              .map(
                (item) => CheckboxListTile(
                  dense: true,
                  value: selected.contains(item.key),
                  title: Text(item.label),
                  subtitle: item.subtitle == null ? null : Text(item.subtitle!),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (checked) {
                    final next = {...selected};
                    if (checked == true) {
                      next.add(item.key);
                    } else {
                      next.remove(item.key);
                    }
                    onChanged(next);
                  },
                ),
              )
              .toList(),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final IconData icon;
  final String message;
  const _Placeholder({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
