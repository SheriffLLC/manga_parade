import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';

class Manga {
  final String id;
  final String title;
  final String coverUrl;
  final String description;
  final List<String> genres;

  final int? catalogScore;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final String? volumes;
  final String? chapters;
  final String? source;
  final String? sourceUrl;
  final String? qiscansSourceUrl;
  final String? asurascansSourceUrl;
  final int? qiscansPostId;

  const Manga({
    required this.id,
    required this.title,
    required this.coverUrl,
    this.description = '',
    this.genres = const [],
    this.catalogScore,
    this.createdAt,
    this.updatedAt,
    this.volumes,
    this.chapters,
    this.source,
    this.sourceUrl,
    this.qiscansSourceUrl,
    this.asurascansSourceUrl,
    this.qiscansPostId,
  });

  static DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory Manga.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      throw ArgumentError('Manga.fromJson called with null');
    }

    try {
      // MangaDex format (if you still use it)
      if (json['type'] == 'manga') {
        final rawId = json['id'] as String;
        final attributes = (json['attributes'] as Map<String, dynamic>?) ?? {};
        final relationships = (json['relationships'] as List<dynamic>?) ?? [];

        String? coverFileName;
        for (final rel in relationships) {
          if (rel is Map && rel['type'] == 'cover_art') {
            final attrs = rel['attributes'];
            if (attrs is Map) {
              coverFileName = attrs['fileName'] as String?;
            }
            break;
          }
        }

        final titles = (attributes['title'] as Map<String, dynamic>?) ?? {};
        final title = (titles['en'] as String?) ??
            titles.values
                .where((v) => v != null && v.toString().isNotEmpty)
                .map((v) => v.toString())
                .cast<String>()
                .firstOrNull ??
            'Unknown Title';

        final description = ((attributes['description']
                as Map<String, dynamic>?)?['en'] as String?) ??
            'No description available';

        final mangaId = 'mangadex_$rawId';
        final coverUrl = coverFileName != null
            ? 'https://uploads.mangadex.org/covers/$rawId/$coverFileName'
            : 'https://via.placeholder.com/200x300?text=No+Cover';

        return Manga(
          id: mangaId,
          title: title,
          coverUrl: coverUrl,
          description: description,
          genres: const [],
          source: 'mangadex',
          sourceUrl: 'https://mangadex.org/title/$rawId',
        );
      }

      // Firestore / regular format
      final id = (json['id'] as String?)?.trim();
      final title = (json['title'] as String?)?.trim();
      final coverUrl = (json['coverUrl'] as String?)?.trim();

      return Manga(
        id: (id == null || id.isEmpty) ? 'unknown' : id,
        title: (title == null || title.isEmpty) ? 'Unknown Title' : title,
        coverUrl: (coverUrl == null || coverUrl.isEmpty)
            ? 'https://via.placeholder.com/200x300?text=No+Cover'
            : coverUrl,
        description:
            (json['description'] as String?) ?? 'No description available',
        genres: (json['genres'] as List?)?.cast<String>() ?? const [],
        catalogScore: (json['catalogScore'] as num?)?.toInt(),
        createdAt: _toDateTime(json['createdAt']),
        updatedAt: _toDateTime(json['updatedAt']),
        volumes: json['volumes'] as String?,
        chapters: json['chapters'] as String?,
        source: json['source'] as String?,
        sourceUrl: json['sourceUrl'] as String?,
        qiscansSourceUrl: json['qiscansSourceUrl'] as String?,
        asurascansSourceUrl: json['asurascansSourceUrl'] as String?,
        qiscansPostId: (json['qiscansPostId'] as num?)?.toInt(),
      );
    } catch (e, st) {
      developer.log('Error parsing manga JSON: $e\nJSON: $json',
          error: e, stackTrace: st);
      throw FormatException('Failed to parse manga data: $e');
    }
  }

  /// IMPORTANT: make this JSON-encodable (no Timestamp objects)
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'coverUrl': coverUrl,
        'description': description,
        'genres': genres,
        'catalogScore': catalogScore,
        'createdAt': createdAt?.millisecondsSinceEpoch,
        'updatedAt': updatedAt?.millisecondsSinceEpoch,
        'volumes': volumes,
        'chapters': chapters,
        'source': source,
        'sourceUrl': sourceUrl,
        'qiscansSourceUrl': qiscansSourceUrl,
        'asurascansSourceUrl': asurascansSourceUrl,
        'qiscansPostId': qiscansPostId,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Manga && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
