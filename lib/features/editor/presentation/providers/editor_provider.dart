import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final activeFileProvider = StateProvider<String?>((ref) => null);
final focusModeProvider = StateProvider<bool>((ref) => false);

final fileContentProvider = FutureProvider<String>((ref) async {
  final path = ref.watch(activeFileProvider);
  if (path == null) return '';
  final file = File(path);
  if (!file.existsSync()) return '';
  return file.readAsString();
});

class EditorState {
  final String content;
  final bool isDirty;

  const EditorState({this.content = '', this.isDirty = false});

  EditorState copyWith({String? content, bool? isDirty}) => EditorState(
        content: content ?? this.content,
        isDirty: isDirty ?? this.isDirty,
      );
}

class EditorNotifier extends Notifier<EditorState> {
  @override
  EditorState build() => const EditorState();

  void updateContent(String content) {
    state = state.copyWith(content: content, isDirty: true);
  }

  Future<void> saveToFile(String path) async {
    await File(path).writeAsString(state.content);
    state = state.copyWith(isDirty: false);
  }

  void loadContent(String content) {
    state = EditorState(content: content, isDirty: false);
  }
}

final editorNotifierProvider = NotifierProvider<EditorNotifier, EditorState>(
  EditorNotifier.new,
);
