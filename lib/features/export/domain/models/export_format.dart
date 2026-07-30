/// Formatos de saída da exportação.
///
/// Quem sabe se um formato pode ser gerado é o mapa de exportadores do
/// `ExportService`, não este enum: um formato listado aqui sem exportador
/// aparece desabilitado no diálogo em vez de falhar na hora de salvar.
enum ExportFormat {
  epub(
    label: 'EPUB',
    description: 'Livro digital (Kindle, Kobo, Apple Books)',
    extension: 'epub',
    mimeType: 'application/epub+zip',
    supportsMetadata: true,
    supportsCover: true,
  ),
  docx(
    label: 'DOCX',
    description: 'Word — o formato que editora e revisor pedem',
    extension: 'docx',
    mimeType:
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    supportsMetadata: true,
    supportsCover: true,
  ),
  pdf(
    label: 'PDF',
    description: 'Miolo diagramado para leitura em tela ou impressão',
    extension: 'pdf',
    mimeType: 'application/pdf',
    supportsMetadata: true,
    supportsCover: true,
  ),
  odt(
    label: 'ODT',
    description: 'OpenDocument (LibreOffice)',
    extension: 'odt',
    mimeType: 'application/vnd.oasis.opendocument.text',
    supportsMetadata: true,
    supportsCover: true,
  ),
  html(
    label: 'HTML',
    description: 'Página única, para ler no navegador',
    extension: 'html',
    mimeType: 'text/html',
    supportsMetadata: true,
    supportsCover: true,
  ),
  txt(
    label: 'TXT',
    description: 'Texto puro, sem formatação',
    extension: 'txt',
    mimeType: 'text/plain',
    supportsMetadata: true,
    supportsCover: false,
  );

  const ExportFormat({
    required this.label,
    required this.description,
    required this.extension,
    required this.mimeType,
    required this.supportsMetadata,
    required this.supportsCover,
  });

  final String label;
  final String description;
  final String extension;
  final String mimeType;

  /// O formato guarda título, autor, ISBN e afins dentro do arquivo.
  final bool supportsMetadata;

  /// O formato tem lugar para uma imagem de capa.
  final bool supportsCover;

  static ExportFormat fromName(String? name) => ExportFormat.values.firstWhere(
        (f) => f.name == name,
        orElse: () => ExportFormat.epub,
      );
}
