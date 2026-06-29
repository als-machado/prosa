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

class EditorDocumentState {
  final String content;
  final bool isDirty;

  const EditorDocumentState({this.content = '', this.isDirty = false});

  EditorDocumentState copyWith({String? content, bool? isDirty}) => EditorDocumentState(
        content: content ?? this.content,
        isDirty: isDirty ?? this.isDirty,
      );
}

class EditorNotifier extends Notifier<EditorDocumentState> {
  @override
  EditorDocumentState build() => const EditorDocumentState();

  void updateContent(String content) {
    state = state.copyWith(content: content, isDirty: true);
  }

  Future<void> saveToFile(String path) async {
    await File(path).writeAsString(state.content);
    state = state.copyWith(isDirty: false);
  }

  void loadContent(String content) {
    state = EditorDocumentState(content: content, isDirty: false);
  }
}

final editorNotifierProvider = NotifierProvider<EditorNotifier, EditorDocumentState>(
  EditorNotifier.new,
);
