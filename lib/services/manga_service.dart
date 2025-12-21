import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:developer' as developer;
import '../models/manga.dart';
import '../models/chapter.dart';
import '../models/page.dart';

class MangaService {
  static const String baseUrl = 'https://api.mangadex.org';
  static const String imageBaseUrl = 'https://uploads.mangadex.org';
  final http.Client _client = http.Client();
  static const int _maxRetries = 3;
  static const Duration _timeout = Duration(seconds: 10);

  Map<String, String> get _headers => {
        'User-Agent': 'MangaParade/1.0.0',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Future<T> _retryRequest<T>(Future<T> Function() request) async {
    int attempts = 0;
    while (attempts < _maxRetries) {
      try {
        return await request();
      } catch (e) {
        attempts++;
        if (attempts == _maxRetries) rethrow;
        await Future.delayed(Duration(seconds: attempts));
      }
    }
    throw Exception('Max retry attempts reached');
  }

  Future<List<Manga>> fetchLatestManga({int page = 1, int limit = 32}) async {
    try {
      final response = await _retryRequest(() => _client.get(
            Uri.parse(
              '$baseUrl/manga?limit=$limit&offset=${(page - 1) * limit}'
              '&order[updatedAt]=desc&includes[]=cover_art'
              '&contentRating[]=safe',
            ),
            headers: _headers,
          ).timeout(_timeout));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['data'] == null) return [];

        return (data['data'] as List)
            .map((mangaData) {
              try {
                return Manga.fromJson(mangaData);
              } catch (e) {
                return null;
              }
            })
            .whereType<Manga>()
            .toList();
      } else {
        throw Exception('Failed to load manga: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching manga: $e');
    }
  }

  Future<List<Chapter>> fetchChapters(String mangaId) async {
    try {
      final response = await _retryRequest(() => _client.get(
            Uri.parse(
              '$baseUrl/manga/$mangaId/feed?translatedLanguage[]=en'
              '&order[chapter]=asc&limit=500&includes[]=scanlation_group'
              '&contentRating[]=safe',
            ),
            headers: _headers,
          ).timeout(_timeout));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['data'] == null) return [];

        final List<Chapter> chapters = [];
        for (final chapterData in data['data']) {
          try {
            if (chapterData['type'] == 'chapter') {
              // Get page count and other chapter data
              final attributes = chapterData['attributes'] as Map<String, dynamic>;
              final relationships = chapterData['relationships'] as List<dynamic>;
              
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

              final pages = await _getChapterPageCount(chapterData['id']);
              
              final chapter = Chapter(
                id: chapterData['id'],
                title: _constructChapterTitle(
                  attributes['volume'] as String?,
                  attributes['chapter'] as String?,
                  attributes['title'] as String?,
                ),
                volume: attributes['volume'] as String?,
                chapter: attributes['chapter'] as String?,
                translatedLanguage: attributes['translatedLanguage'] as String? ?? 'en',
                scanlationGroup: scanlationGroup,
                publishAt: DateTime.parse(attributes['publishAt'] as String),
                pages: pages,
              );
              
              chapters.add(chapter);
            }
          } catch (e) {
            // Skip failed chapter and continue with others
            continue;
          }
        }

        return chapters..sort((a, b) {
          final volumeCompare = (a.volume ?? '').compareTo(b.volume ?? '');
          if (volumeCompare != 0) return volumeCompare;
          
          final aNum = double.tryParse(a.chapter ?? '0') ?? 0;
          final bNum = double.tryParse(b.chapter ?? '0') ?? 0;
          return aNum.compareTo(bNum);
        });
      } else {
        throw Exception('Failed to load chapters: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching chapters: $e');
    }
  }

  String _constructChapterTitle(String? volume, String? chapter, String? title) {
    final parts = <String>[];
    
    if (volume != null) {
      parts.add('Vol. $volume');
    }
    if (chapter != null) {
      parts.add('Ch. $chapter');
    }
    if (title != null && title.isNotEmpty) {
      parts.add('- $title');
    }
    
    return parts.isEmpty ? 'Unknown Chapter' : parts.join(' ');
  }

  Future<int> _getChapterPageCount(String chapterId) async {
    try {
      final response = await _retryRequest(() => _client.get(
            Uri.parse('$baseUrl/at-home/server/$chapterId'),
            headers: _headers,
          ).timeout(_timeout));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['chapter']?['data'] == null) return 0;
        return (data['chapter']['data'] as List).length;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  Future<List<MangaPage>> fetchPages(String chapterId) async {
    try {
      final response = await _retryRequest(() => _client.get(
            Uri.parse('$baseUrl/at-home/server/$chapterId'),
            headers: _headers,
          ).timeout(_timeout));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['chapter'] == null) return [];

        final baseUrl = data['baseUrl'];
        final hash = data['chapter']['hash'];
        final pages = data['chapter']['data'] as List;

        return List.generate(
          pages.length,
          (index) {
            try {
              return MangaPage(
                id: '$chapterId-$index',
                imageUrl: '$baseUrl/data/$hash/${pages[index]}',
                number: index + 1,
              );
            } catch (e) {
              return null;
            }
          },
        ).whereType<MangaPage>().toList();
      } else {
        throw Exception('Failed to load pages: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching pages: $e');
    }
  }

  void dispose() {
    _client.close();
  }
}
