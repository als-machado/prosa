import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/file_name_sanitizer.dart';

class NewChapterDialog extends StatefulWidget {
  final String projectPath;
  const NewChapterDialog({super.key, required this.projectPath});

  @override
  State<NewChapterDialog> createState() => _NewChapterDialogState();
}

class _NewChapterDialogState extends State<NewChapterDialog> {
  final _titleCtrl = TextEditingController();
  bool _useScenes = false;
  int _number = 1;

  @override
  void initState() {
    super.initState();
    final chaptersDir = Directory('${widget.projectPath}/${AppConstants.chaptersDir}');
    if (chaptersDir.existsSync()) {
      _number = chaptersDir.listSync().whereType<Directory>().length + 1;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  void _create() {
    final title = sanitizeFileName(_titleCtrl.text);
    final dirName = title.isNotEmpty ? '$_number - $title' : '$_number';
    final chapterDir = Directory('${widget.projectPath}/${AppConstants.chaptersDir}/$dirName');
    chapterDir.createSync(recursive: true);

    if (_useScenes) {
      File('${chapterDir.path}/scene 1.md').writeAsStringSync('');
    } else {
      File('${chapterDir.path}/${AppConstants.chapterFile}').writeAsStringSync('# $dirName\n\n');
    }

    Navigator.pop(context, dirName);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo capítulo'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('Número: '),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: _number > 1 ? () => setState(() => _number--) : null,
                ),
                Text('$_number', style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => setState(() => _number++),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Título (opcional)',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Dividir em cenas'),
              value: _useScenes,
              onChanged: (v) => setState(() => _useScenes = v),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _create, child: const Text('Criar')),
      ],
    );
  }
}
