import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/file_name_sanitizer.dart';

class NewCharacterDialog extends StatefulWidget {
  final String projectPath;
  const NewCharacterDialog({super.key, required this.projectPath});

  @override
  State<NewCharacterDialog> createState() => _NewCharacterDialogState();
}

class _NewCharacterDialogState extends State<NewCharacterDialog> {
  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _create() {
    final name = sanitizeFileName(_nameCtrl.text);
    if (name.isEmpty) return;
    final dir = Directory('${widget.projectPath}/${AppConstants.charactersDir}/$name');
    dir.createSync(recursive: true);
    File('${dir.path}/${AppConstants.characteristicsFile}').writeAsStringSync('# $name — Características\n\n');
    File('${dir.path}/${AppConstants.evolutionFile}').writeAsStringSync('# $name — Evolução\n\n');
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo personagem'),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Nome do personagem',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (_) => _create(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _create, child: const Text('Criar')),
      ],
    );
  }
}
