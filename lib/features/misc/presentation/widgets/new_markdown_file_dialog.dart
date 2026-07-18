import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/utils/file_name_sanitizer.dart';

/// Cria um arquivo .md dentro de uma pasta de misc/ (notas, locais, …).
/// Devolve o nome criado via Navigator.pop, ou null se cancelado.
class NewMarkdownFileDialog extends StatefulWidget {
  final String dirPath;
  final String sectionLabel;
  const NewMarkdownFileDialog({super.key, required this.dirPath, required this.sectionLabel});

  @override
  State<NewMarkdownFileDialog> createState() => _NewMarkdownFileDialogState();
}

class _NewMarkdownFileDialogState extends State<NewMarkdownFileDialog> {
  final _nameCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = sanitizeFileName(_nameCtrl.text);
    if (name.isEmpty) {
      setState(() => _error = 'Informe um nome válido');
      return;
    }
    final file = File('${widget.dirPath}/$name.md');
    if (file.existsSync()) {
      setState(() => _error = 'Já existe um arquivo com esse nome');
      return;
    }
    await Directory(widget.dirPath).create(recursive: true);
    await file.writeAsString('# $name\n\n');
    if (mounted) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Novo item em "${widget.sectionLabel}"'),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: 'Nome',
            border: const OutlineInputBorder(),
            errorText: _error,
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
