import 'dart:developer' as developer;
import 'dart:math';

class Manga {
  final String id;
  final String title;
  final String coverUrl;
  final String description;
  final List<String> genres;
  final String? volumes;
  final String? chapters;

  const Manga({
    required this.id,
    required this.title,
    required this.coverUrl,
    this.description = '',
    this.genres = const [],
    this.volumes,
    this.chapters,
  });

  factory Manga.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      throw ArgumentError('Manga.fromJson called with null');
    }

    try {
      // Handle MangaDex format
      if (json['type'] == 'manga') {
        final id = json['id'] as String;
        final attributes = json['attributes'] as Map<String, dynamic>;
        final relationships = json['relationships'] as List<dynamic>;
        String? coverFileName;

        // Find cover art relationship
        for (final rel in relationships) {
          if (rel['type'] == 'cover_art') {
            developer.log('Found cover_art relationship: $rel');
            final attrs = rel['attributes'];
            if (attrs != null) {
              coverFileName = attrs['fileName'] as String?;
              developer.log('Cover filename: $coverFileName');
            }
            break;
          }
        }

        // Get title in English or first available language
        final titles = attributes['title'] as Map<String, dynamic>;
        String title;
        try {
          title = titles['en'] ?? titles.values.firstWhere(
            (v) => v != null && v.toString().isNotEmpty,
            orElse: () => 'Unknown Title',
          ) as String;
        } catch (e) {
          developer.log('Error getting title: $e\nTitles data: $titles');
          title = 'Unknown Title';
        }

        final description = ((attributes['description'] as Map<String, dynamic>?)
                    ?['en'] as String?) ??
                'No description available';

        final mangaId = 'mangadex_$id';
        final coverUrl = coverFileName != null
            ? 'https://uploads.mangadex.org/covers/$id/$coverFileName'
            : 'https://via.placeholder.com/200x300?text=No+Cover';

        final genres = (attributes['genres'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
            [];

        return Manga(
          id: mangaId,
          title: title,
          coverUrl: coverUrl,
          description: description,
          genres: genres,
          volumes: json['volumes'] as String?,
          chapters: json['chapters'] as String?,
        );
      }

      // Handle regular format (e.g., from cache or reading history)
      return Manga(
        id: json['id'] as String? ?? 'unknown',
        title: json['title'] as String? ?? 'Unknown Title',
        coverUrl: json['coverUrl'] as String? ?? 'https://via.placeholder.com/200x300?text=No+Cover',
        description: json['description'] as String? ?? 'No description available',
        genres: (json['genres'] as List<dynamic>?)?.cast<String>() ?? [],
        volumes: json['volumes'] as String?,
        chapters: json['chapters'] as String?,
      );
    } catch (e, stackTrace) {
      developer.log(
        'Error parsing manga JSON: $e\nJSON: $json',
        error: e,
        stackTrace: stackTrace,
      );
      throw FormatException('Failed to parse manga data: $e');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'coverUrl': coverUrl,
    'description': description,
    'genres': genres,
    'volumes': volumes,
    'chapters': chapters,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Manga && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
