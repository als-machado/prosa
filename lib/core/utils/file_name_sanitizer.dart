/// Torna um nome digitado pelo usuário seguro para virar arquivo/diretório.
///
/// Sem isso, um capítulo chamado "../../x" criaria diretórios fora do
/// projeto, e um "/" no meio do nome quebraria a estrutura em disco.
/// Retorna string vazia se não sobrar nada utilizável.
String sanitizeFileName(String input) {
  var name = input.trim().replaceAll(RegExp(r'[/\\:*?"<>|\x00]'), '-');
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Remove pontos iniciais: evita nomes ocultos e ".."/"." como resultado.
  name = name.replaceFirst(RegExp(r'^\.+'), '').trim();
  return name;
}
