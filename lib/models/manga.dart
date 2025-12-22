import 'package:cloud_firestore/cloud_firestore.dart';

class MangaSource {
  final String key; // e.g. "mangakakalot", "qiscans", "manual_seed"
  final String seriesUrl;
  final String? seriesId;
  final DateTime? lastSeenAt;
  final String status; // ok|dead|blocked|unknown

  const MangaSource({
    required this.key,
    required this.seriesUrl,
    this.seriesId,
    this.lastSeenAt,
    this.status = 'unknown',
  });

  factory MangaSource.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const MangaSource(
          key: 'unknown', seriesUrl: '', status: 'unknown');
    }

    return MangaSource(
      key: (json['key'] as String?)?.trim().isNotEmpty == true
          ? (json['key'] as String).trim()
          : 'unknown',
      seriesUrl: (json['seriesUrl'] as String?) ?? '',
      seriesId: json['seriesId'] as String?,
      lastSeenAt: _asDateTime(json['lastSeenAt']),
      status: (json['status'] as String?) ?? 'unknown',
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'seriesUrl': seriesUrl,
        if (seriesId != null) 'seriesId': seriesId,
        if (lastSeenAt != null) 'lastSeenAt': Timestamp.fromDate(lastSeenAt!),
        'status': status,
      };
}

class Manga {
  final String id;
  final String title;
  final String coverUrl;

  final String description;
  final List<String> genres;

  /// Firestore contract fields
  final DateTime? updatedAt;
  final DateTime? createdAt;
  final double catalogScore;
  final List<MangaSource> sources;

  /// Legacy / optional (keep for compatibility with old app)
  final String? volumes;
  final String? chapters;

  const Manga({
    required this.id,
    required this.title,
    required this.coverUrl,
    this.description = '',
    this.genres = const [],
    this.updatedAt,
    this.createdAt,
    this.catalogScore = 0,
    this.sources = const [],
    this.volumes,
    this.chapters,
  });

  /// Parses either:
  /// - Firestore docs (our new canonical format)
  /// - Legacy cache/scrape formats (older app)
  /// - MangaDex API items (legacy support)
  factory Manga.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      throw ArgumentError('Manga.fromJson called with null');
    }

    // --- MangaDex legacy support (leave it, but don't let it crash) ---
    if (json['type'] == 'manga' && json['id'] != null) {
      final rawId = json['id'].toString();
      final mangaId = 'mangadex_$rawId';

      final attributes =
          (json['attributes'] as Map?)?.cast<String, dynamic>() ?? {};
      final relationships = (json['relationships'] as List?) ?? const [];

      String? coverFileName;
      for (final rel in relationships) {
        final relMap = (rel as Map?)?.cast<String, dynamic>();
        if (relMap == null) continue;
        if (relMap['type'] == 'cover_art') {
          final attrs = (relMap['attributes'] as Map?)?.cast<String, dynamic>();
          coverFileName = attrs?['fileName'] as String?;
          break;
        }
      }

      final titleMap =
          (attributes['title'] as Map?)?.cast<String, dynamic>() ?? {};
      final title = (titleMap['en'] as String?) ??
          titleMap.values.map((v) => v?.toString() ?? '').firstWhere(
              (v) => v.trim().isNotEmpty,
              orElse: () => 'Unknown Title');

      final descMap =
          (attributes['description'] as Map?)?.cast<String, dynamic>();
      final description =
          (descMap?['en'] as String?) ?? 'No description available';

      final coverUrl = coverFileName != null
          ? 'https://uploads.mangadex.org/covers/$rawId/$coverFileName'
          : 'https://via.placeholder.com/200x300?text=No+Cover';

      return Manga(
        id: mangaId,
        title: title,
        coverUrl: coverUrl,
        description: description,
        genres: const [],
        catalogScore: 0,
        sources: const [
          MangaSource(key: 'mangadex', seriesUrl: '', status: 'unknown')
        ],
      );
    }

    // --- Firestore / canonical format ---
    final id = (json['id'] as String?)?.trim().isNotEmpty == true
        ? (json['id'] as String).trim()
        : 'unknown';

    final title = (json['title'] as String?) ?? 'Unknown Title';
    final coverUrl = (json['coverUrl'] as String?) ??
        'https://via.placeholder.com/200x300?text=No+Cover';

    final description =
        (json['description'] as String?) ?? 'No description available';

    final genres = (json['genres'] is List)
        ? (json['genres'] as List).map((e) => e.toString()).toList()
        : <String>[];

    final updatedAt = _asDateTime(json['updatedAt']);
    final createdAt = _asDateTime(json['createdAt']);

    final catalogScore = _asDouble(json['catalogScore']) ?? 0;

    final sourcesRaw = json['sources'];
    final sources = <MangaSource>[];
    if (sourcesRaw is List) {
      for (final item in sourcesRaw) {
        if (item is Map) {
          sources.add(MangaSource.fromJson(item.cast<String, dynamic>()));
        }
      }
    }

    return Manga(
      id: id,
      title: title,
      coverUrl: coverUrl,
      description: description,
      genres: genres,
      updatedAt: updatedAt,
      createdAt: createdAt,
      catalogScore: catalogScore,
      sources: sources,
      // legacy
      volumes: json['volumes'] as String?,
      chapters: json['chapters'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'coverUrl': coverUrl,
        'description': description,
        'genres': genres,
        'catalogScore': catalogScore,
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        'sources': sources.map((s) => s.toJson()).toList(),
        if (volumes != null) 'volumes': volumes,
        if (chapters != null) 'chapters': chapters,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Manga && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

// ---- helpers ----

DateTime? _asDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is Timestamp) return value.toDate();
  if (value is int) {
    // epoch millis
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is String) {
    // ISO string
    return DateTime.tryParse(value);
  }
  return null;
}

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
