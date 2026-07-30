import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final activeFileProvider = StateProvider<String?>((ref) => null);
final focusModeProvider = StateProvider<bool>((ref) => false);

/// Mostra o Markdown como texto, em vez de renderizado.
///
/// Vale para a sessão e não para o arquivo: é um jeito de olhar o texto, e o
/// autor que abre o modo texto para conferir uma tabela quer continuar nele ao
/// pular para o capítulo seguinte.
final rawModeProvider = StateProvider<bool>((ref) => false);

final fileContentProvider = FutureProvider<String>((ref) async {
  final path = ref.watch(activeFileProvider);
  if (path == null) return '';
  final file = File(path);
  if (!await file.exists()) return '';
  return file.readAsString();
});

/// Guarda apenas a flag de alterações pendentes. O conteúdo vive no
/// EditorState do AppFlowy e só é serializado para Markdown no momento
/// do save — serializar a cada tecla custa O(documento) por caractere.
class EditorNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void markDirty() {
    if (!state) state = true;
  }

  void reset() => state = false;

  Future<void> saveToFile(String path, String content) async {
    await File(path).writeAsString(content);
    state = false;
  }
}

final editorNotifierProvider = NotifierProvider<EditorNotifier, bool>(
  EditorNotifier.new,
);
