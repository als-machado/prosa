import '../../../../shared/models/prosa_project.dart';

/// Metadados do livro gravados dentro do arquivo exportado.
///
/// Nasce do `.prosa` (título, autor, idioma) e é editável no diálogo de
/// exportação; o que o autor preencher fica guardado no projeto pelo
/// `ExportConfigStore`, senão ele redigitaria ISBN e editora a cada exportação.
class BookMetadata {
  final String title;
  final String author;

  /// Código BCP-47 — 'pt-BR', 'en-US'. É o mesmo campo `language` do `.prosa`.
  final String language;
  final String publisher;
  final String description;

  /// Aviso de direitos autorais ("© 2026 Fulano").
  final String rights;

  /// ISBN, quando houver. Sem ele o livro é identificado por um UUID.
  final String isbn;

  /// Gêneros/assuntos — viram um `dc:subject` cada.
  final List<String> subjects;
  final DateTime? publishedAt;

  const BookMetadata({
    this.title = '',
    this.author = '',
    this.language = 'pt-BR',
    this.publisher = '',
    this.description = '',
    this.rights = '',
    this.isbn = '',
    this.subjects = const [],
    this.publishedAt,
  });

  factory BookMetadata.fromProject(ProsaProject project) => BookMetadata(
        title: project.title,
        author: project.author,
        language: project.language,
        subjects: project.genre.isEmpty ? const [] : [project.genre],
        rights: project.author.isEmpty
            ? ''
            : '© ${project.createdAt.year} ${project.author}',
      );

  BookMetadata copyWith({
    String? title,
    String? author,
    String? language,
    String? publisher,
    String? description,
    String? rights,
    String? isbn,
    List<String>? subjects,
    DateTime? publishedAt,
    bool clearPublishedAt = false,
  }) =>
      BookMetadata(
        title: title ?? this.title,
        author: author ?? this.author,
        language: language ?? this.language,
        publisher: publisher ?? this.publisher,
        description: description ?? this.description,
        rights: rights ?? this.rights,
        isbn: isbn ?? this.isbn,
        subjects: subjects ?? this.subjects,
        publishedAt:
            clearPublishedAt ? null : (publishedAt ?? this.publishedAt),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'author': author,
        'language': language,
        'publisher': publisher,
        'description': description,
        'rights': rights,
        'isbn': isbn,
        'subjects': subjects,
        if (publishedAt != null)
          'published_at': publishedAt!.toIso8601String().split('T').first,
      };

  factory BookMetadata.fromJson(Map<String, dynamic> json) => BookMetadata(
        title: json['title'] as String? ?? '',
        author: json['author'] as String? ?? '',
        language: json['language'] as String? ?? 'pt-BR',
        publisher: json['publisher'] as String? ?? '',
        description: json['description'] as String? ?? '',
        rights: json['rights'] as String? ?? '',
        isbn: json['isbn'] as String? ?? '',
        subjects: (json['subjects'] as List?)?.cast<String>() ?? const [],
        publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      );
}
