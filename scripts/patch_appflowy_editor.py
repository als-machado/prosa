"""
Patches no appflowy_editor 6.2.0 publicado no pub.dev. Roda após
`flutter pub get` (o pub cache é global por máquina, não por projeto —
precisa rodar de novo se o cache for limpo ou o pacote reinstalado).
"""
import os
import sys

PKG_ROOT = os.path.expanduser('~/.pub-cache/hosted/pub.dev/appflowy_editor-6.2.0')


def patch_on_focus_received():
    """
    Adiciona o override de onFocusReceived, que se tornou abstrato no
    Flutter 3.44 e está ausente no pacote publicado — sem isto o app
    nem compila.
    """
    path = f'{PKG_ROOT}/lib/src/editor/editor_component/service/ime/delta_input_service.dart'
    if not os.path.exists(path):
        print(f'Arquivo não encontrado: {path}', file=sys.stderr)
        return False

    with open(path, 'r') as f:
        content = f.read()

    if 'onFocusReceived' in content:
        print('onFocusReceived: já estava corrigido.')
        return True

    patched = content.replace(
        '  @override\n  TextEditingValue? currentTextEditingValue;',
        '  @override\n  bool onFocusReceived() => false;\n\n'
        '  @override\n  TextEditingValue? currentTextEditingValue;',
    )

    if patched == content:
        print('onFocusReceived: padrão não encontrado — patch não aplicado.', file=sys.stderr)
        return False

    with open(path, 'w') as f:
        f.write(patched)
    print('onFocusReceived: patch aplicado.')
    return True


def patch_redo_clears_redo_stack():
    """
    UndoManager.redo() reaplica a transação com `recordUndo: true`, que
    passa por getUndoHistoryItem(). Essa função limpa o redoStack inteiro
    sempre que o topo do undoStack já está selado — o que é quase sempre
    verdade (edição normal sela o item após ~1s). Resultado: ao desfazer
    várias alterações e refazer uma, o resto da pilha de refazer some.

    Fix: redo() passa a empilhar manualmente no undoStack (já selado),
    sem passar por getUndoHistoryItem() — só uma edição nova de verdade
    deve limpar o redoStack, não o próprio ato de refazer.
    """
    path = f'{PKG_ROOT}/lib/src/history/undo_manager.dart'
    if not os.path.exists(path):
        print(f'Arquivo não encontrado: {path}', file=sys.stderr)
        return False

    with open(path, 'r') as f:
        content = f.read()

    marker = '// prosa: redo patch aplicado'
    if marker in content:
        print('redo(): já estava corrigido.')
        return True

    old = '''  void redo() {
    AppFlowyEditorLog.editor.debug('redo');
    final s = state;
    if (s == null) {
      return;
    }
    final historyItem = redoStack.pop();
    if (historyItem == null) {
      return;
    }
    final transaction = historyItem.toTransaction(s);
    s.apply(
      transaction,
      options: const ApplyOptions(
        recordUndo: true,
        recordRedo: false,
      ),
    );
  }'''

    new = '''  void redo() {
    // prosa: redo patch aplicado
    AppFlowyEditorLog.editor.debug('redo');
    final s = state;
    if (s == null) {
      return;
    }
    final historyItem = redoStack.pop();
    if (historyItem == null) {
      return;
    }
    final transaction = historyItem.toTransaction(s);
    s.apply(
      transaction,
      options: const ApplyOptions(
        recordUndo: false,
        recordRedo: false,
      ),
    );
    final undoItem = HistoryItem()
      ..addAll(transaction.operations)
      ..beforeSelection = transaction.beforeSelection
      ..afterSelection = transaction.afterSelection
      ..seal();
    undoStack.push(undoItem);
  }'''

    if old not in content:
        print('redo(): padrão não encontrado — patch não aplicado.', file=sys.stderr)
        return False

    with open(path, 'w') as f:
        f.write(content.replace(old, new))
    print('redo(): patch aplicado.')
    return True


if __name__ == '__main__':
    ok = patch_on_focus_received()
    ok = patch_redo_clears_redo_stack() and ok
    sys.exit(0 if ok else 1)
