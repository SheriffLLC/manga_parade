import 'dart:developer' as developer;

class Chapter {
  final String id;
  final String title;
  final String? volume;
  final String? chapter;
  final String translatedLanguage;
  final String? scanlationGroup;
  final DateTime publishAt;
  final int pages;

  const Chapter({
    required this.id,
    required this.title,
    this.volume,
    this.chapter,
    required this.translatedLanguage,
    this.scanlationGroup,
    required this.publishAt,
    required this.pages,
  });

  factory Chapter.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      throw ArgumentError('Chapter.fromJson called with null');
    }

    try {
      // Handle MangaDex format
      if (json.containsKey('attributes')) {
        final id = json['id'] as String;
        final attributes = json['attributes'] as Map<String, dynamic>;
        final relationships = json['relationships'] as List<dynamic>;

        String? scanlationGroup;
        for (final rel in relationships) {
          if (rel['type'] == 'scanlation_group') {
            final attrs = rel['attributes'];
            if (attrs != null) {
              scanlationGroup = attrs['name'] as String?;
            }
            break;
          }
        }

        // Construct title from volume and chapter numbers
        final volume = attributes['volume'] as String?;
        final chapter = attributes['chapter'] as String?;
        String title = '';
        
        if (volume != null) {
          title += 'Vol. $volume ';
        }
        if (chapter != null) {
          title += 'Ch. $chapter';
        }
        if (title.isEmpty) {
          title = 'Unknown Chapter';
        }

        return Chapter(
          id: id,
          title: title,
          volume: volume,
          chapter: chapter,
          translatedLanguage: attributes['translatedLanguage'] as String? ?? 'unknown',
          scanlationGroup: scanlationGroup,
          publishAt: DateTime.parse(attributes['publishAt'] as String? ?? DateTime.now().toIso8601String()),
          pages: attributes['pages'] as int? ?? 0,
        );
      }

      // Handle regular format (e.g., from cache or reading history)
      return Chapter(
        id: json['id'] as String? ?? 'unknown',
        title: json['title'] as String? ?? 'Unknown Chapter',
        volume: json['volume'] as String?,
        chapter: json['chapter'] as String?,
        translatedLanguage: json['translatedLanguage'] as String? ?? 'unknown',
        scanlationGroup: json['scanlationGroup'] as String?,
        publishAt: json['publishAt'] != null 
            ? DateTime.parse(json['publishAt'] as String)
            : DateTime.now(),
        pages: json['pages'] as int? ?? 0,
      );
    } catch (e, stackTrace) {
      developer.log(
        'Error parsing chapter JSON: $e\nJSON: $json',
        error: e,
        stackTrace: stackTrace,
      );
      throw FormatException('Failed to parse chapter data: $e');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'volume': volume,
    'chapter': chapter,
    'translatedLanguage': translatedLanguage,
    'scanlationGroup': scanlationGroup,
    'publishAt': publishAt.toIso8601String(),
    'pages': pages,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Chapter && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
