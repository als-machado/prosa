import 'dart:io';
import 'package:flutter/material.dart';

class NewSceneDialog extends StatefulWidget {
  final String chapterPath;
  final String chapterName;
  const NewSceneDialog({super.key, required this.chapterPath, required this.chapterName});

  @override
  State<NewSceneDialog> createState() => _NewSceneDialogState();
}

class _NewSceneDialogState extends State<NewSceneDialog> {
  late int _number;

  @override
  void initState() {
    super.initState();
    final dir = Directory(widget.chapterPath);
    final scenes = dir.existsSync()
        ? dir.listSync().whereType<File>().where((f) => f.path.contains('scene ')).length
        : 0;
    _number = scenes + 1;
  }

  void _create() {
    final file = File('${widget.chapterPath}/scene $_number.md');
    file.writeAsStringSync('');
    Navigator.pop(context, 'scene $_number.md');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Nova cena em "${widget.chapterName}"'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Número da cena: '),
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
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _create, child: const Text('Criar')),
      ],
    );
  }
}
