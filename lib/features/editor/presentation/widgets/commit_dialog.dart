import 'package:flutter/material.dart';

class CommitDialog extends StatefulWidget {
  const CommitDialog({super.key});

  @override
  State<CommitDialog> createState() => _CommitDialogState();
}

class _CommitDialogState extends State<CommitDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Criar commit'),
      content: SizedBox(
        width: 400,
        child: TextField(
          controller: _ctrl,
          decoration: const InputDecoration(
            labelText: 'Mensagem do commit',
            hintText: 'Descreva o que foi alterado...',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          maxLines: 3,
          onSubmitted: (_) => _confirm(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _confirm, child: const Text('Commit')),
      ],
    );
  }

  void _confirm() {
    final msg = _ctrl.text.trim();
    if (msg.isEmpty) return;
    Navigator.pop(context, msg);
  }
}
