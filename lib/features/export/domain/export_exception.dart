/// Erro de exportação com mensagem já pronta para o usuário.
///
/// O diálogo mostra `toString()` direto, então a mensagem tem de fazer sentido
/// para quem escreve o livro, não para quem escreve o código.
class ExportException implements Exception {
  final String message;
  const ExportException(this.message);

  @override
  String toString() => message;
}
