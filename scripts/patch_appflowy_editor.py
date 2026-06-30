"""
Patch appflowy_editor 6.2.0 to add the missing onFocusReceived override.
The published package on pub.dev is missing this method, which became
abstract in Flutter 3.44. Run after `flutter pub get`.
"""
import os
import sys

path = os.path.expanduser(
    '~/.pub-cache/hosted/pub.dev/appflowy_editor-6.2.0'
    '/lib/src/editor/editor_component/service/ime/delta_input_service.dart'
)

if not os.path.exists(path):
    print(f'Arquivo não encontrado: {path}', file=sys.stderr)
    sys.exit(1)

with open(path, 'r') as f:
    content = f.read()

if 'onFocusReceived' in content:
    print('Já estava corrigido.')
    sys.exit(0)

patched = content.replace(
    '  @override\n  TextEditingValue? currentTextEditingValue;',
    '  @override\n  bool onFocusReceived() => false;\n\n'
    '  @override\n  TextEditingValue? currentTextEditingValue;',
)

if patched == content:
    print('Padrão não encontrado — patch não aplicado.', file=sys.stderr)
    sys.exit(1)

with open(path, 'w') as f:
    f.write(patched)

print('Patch aplicado.')
