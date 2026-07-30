/// Formatos de saída da exportação.
///
/// Só o EPUB está implementado; os outros aparecem desabilitados no diálogo
/// para que o caminho até eles já esteja no lugar — cada um é só um
/// `BookExporter` novo sobre o mesmo `Book`.
enum ExportFormat {
  epub(
    label: 'EPUB',
    description: 'Livro digital (Kindle, Kobo, Apple Books)',
    extension: 'epub',
    mimeType: 'application/epub+zip',
    available: true,
    supportsMetadata: true,
    supportsCover: true,
  ),
  docx(
    label: 'DOCX',
    description: 'Word — o formato que editora e revisor pedem',
    extension: 'docx',
    mimeType:
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    available: false,
    supportsMetadata: true,
    supportsCover: false,
  ),
  pdf(
    label: 'PDF',
    description: 'Miolo diagramado para leitura em tela ou impressão',
    extension: 'pdf',
    mimeType: 'application/pdf',
    available: false,
    supportsMetadata: true,
    supportsCover: true,
  ),
  odt(
    label: 'ODT',
    description: 'OpenDocument (LibreOffice)',
    extension: 'odt',
    mimeType: 'application/vnd.oasis.opendocument.text',
    available: false,
    supportsMetadata: true,
    supportsCover: false,
  ),
  html(
    label: 'HTML',
    description: 'Página única, para ler no navegador',
    extension: 'html',
    mimeType: 'text/html',
    available: false,
    supportsMetadata: false,
    supportsCover: true,
  ),
  txt(
    label: 'TXT',
    description: 'Texto puro, sem formatação',
    extension: 'txt',
    mimeType: 'text/plain',
    available: false,
    supportsMetadata: false,
    supportsCover: false,
  );

  const ExportFormat({
    required this.label,
    required this.description,
    required this.extension,
    required this.mimeType,
    required this.available,
    required this.supportsMetadata,
    required this.supportsCover,
  });

  final String label;
  final String description;
  final String extension;
  final String mimeType;

  /// Falso enquanto o exportador do formato não existe.
  final bool available;

  /// O formato guarda título, autor, ISBN e afins dentro do arquivo.
  final bool supportsMetadata;

  /// O formato tem lugar para uma imagem de capa.
  final bool supportsCover;

  static ExportFormat fromName(String? name) => ExportFormat.values.firstWhere(
        (f) => f.name == name,
        orElse: () => ExportFormat.epub,
      );
}
