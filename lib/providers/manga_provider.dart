import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:html/parser.dart' as parser;
import '../models/manga.dart';
import '../models/chapter.dart';
import '../models/manga_page.dart';

class MangaProvider with ChangeNotifier {
  final List<Manga> _mangas = [];
  bool _isLoading = false;
  String? _error;
  int _currentPage = 1;
  bool _hasMorePages = true;
  static const int _limit = 32;
  bool _disposed = false;
  final _client = http.Client();
  late SharedPreferences _prefs;
  static const String _cacheKey = 'manga_cache';
  static const String _chapterPagesCache = 'chapter_pages_cache';
  static const Duration _cacheDuration = Duration(hours: 24);

  List<Manga> get mangas => List.unmodifiable(_mangas);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasMorePages => _hasMorePages;

  MangaProvider() {
    _initSharedPreferences();
  }

  Future<void> _initSharedPreferences() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<void> _saveToCache(List<Manga> mangas) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final cacheData = {
        'timestamp': timestamp,
        'mangas': mangas.map((m) => m.toJson()).toList(),
      };
      await _prefs.setString(_cacheKey, json.encode(cacheData));
    } catch (e) {
    }
  }

  Future<List<Manga>?> _loadFromCache() async {
    try {
      final cacheString = _prefs.getString(_cacheKey);
      if (cacheString == null) return null;

      final cacheData = json.decode(cacheString) as Map<String, dynamic>;
      final timestamp = cacheData['timestamp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      if (now - timestamp > _cacheDuration.inMilliseconds) {
        return null;
      }

      final List<dynamic> mangaList = cacheData['mangas'];
      final mangas = mangaList.map((m) => Manga.fromJson(m)).toList();
      return mangas;
    } catch (e) {
      return null;
    }
  }

  Future<List<Manga>?> _fetchFromFallbackSource() async {
    try {
      final response = await _client.get(
        Uri.parse('https://mangadex.org'),
        headers: {'User-Agent': 'MangaParade/1.0.0'},
      );

      if (response.statusCode != 200) return null;

      final document = parser.parse(response.body);
      final mangaElements = document.querySelectorAll('.manga-card');
      final mangas = <Manga>[];

      for (var element in mangaElements) {
        try {
          final titleElement = element.querySelector('.manga-title');
          final coverElement = element.querySelector('img');
          final idMatch = element.querySelector('a')?.attributes['href']?.split('/').last;

          if (titleElement != null && coverElement != null && idMatch != null) {
            mangas.add(Manga(
              id: 'mangadex_$idMatch',
              title: titleElement.text.trim(),
              coverUrl: coverElement.attributes['src'] ?? '',
              description: '',
            ));
          }
        } catch (e) {
        }
      }

      if (mangas.isNotEmpty) {
        return mangas;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> fetchMangas({bool refresh = false, bool notify = true}) async {
    if (_isLoading) return;

    try {
      _setLoading(true, notify: notify);

      if (refresh) {
        _currentPage = 1;
        _hasMorePages = true;
        _mangas.clear();
        if (notify) notifyListeners();
      }

      // Try loading from cache first if it's a refresh
      if (refresh) {
        final cachedMangas = await _loadFromCache();
        if (cachedMangas != null) {
          _mangas.addAll(cachedMangas);
          _error = null;
          _setLoading(false, notify: notify);
          return;
        }
      }

      // Try MangaDex API
      final mangas = await _fetchFromMangaDexApi();
      if (mangas != null) {
        _mangas.addAll(mangas);
        await _saveToCache(_mangas);
        _error = null;
        _setLoading(false, notify: notify);
        return;
      }

      // Try fallback source
      final fallbackMangas = await _fetchFromFallbackSource();
      if (fallbackMangas != null) {
        _mangas.addAll(fallbackMangas);
        await _saveToCache(_mangas);
        _error = null;
        _setLoading(false, notify: notify);
        return;
      }

      throw Exception('Failed to load manga from all sources');
    } catch (e, stackTrace) {
      _error = 'Error loading manga: $e';
    } finally {
      _setLoading(false, notify: notify);
    }
  }

  Future<List<Manga>?> _fetchFromMangaDexApi() async {
    try {
      final url = Uri.parse(
        'https://api.mangadex.org/manga'
        '?includes[]=cover_art'
        '&contentRating[]=safe'
        '&hasAvailableChapters=true'
        '&order[followedCount]=desc'
        '&limit=$_limit'
        '&offset=${(_currentPage - 1) * _limit}'
      );

      int maxRetries = 3;
      int currentTry = 0;
      http.Response? response;
      
      while (currentTry < maxRetries) {
        try {
          response = await _client.get(
            url,
            headers: {
              'User-Agent': 'MangaParade/1.0.0',
              'Accept': 'application/json',
            },
          );
          
          if (response.statusCode != 500) {
            break;
          }
          
          currentTry++;
          if (currentTry < maxRetries) {
            await Future.delayed(Duration(seconds: 1));
          }
        } catch (e) {
          currentTry++;
          if (currentTry < maxRetries) {
            await Future.delayed(Duration(seconds: 1));
          }
        }
      }

      if (response == null || response.statusCode != 200) {
        return null;
      }

      final data = json.decode(response.body);
      if (!data.containsKey('data')) {
        return null;
      }

      final List<dynamic> mangaList = data['data'];
      final total = data['total'] as int? ?? 0;
      _hasMorePages = (_currentPage - 1) * _limit + mangaList.length < total;
      _currentPage++;

      return mangaList.map((mangaData) => Manga.fromJson(mangaData)).toList();
    } catch (e) {
      return null;
    }
  }

  void _setLoading(bool value, {bool notify = true}) {
    if (_isLoading != value) {
      _isLoading = value;
      if (notify && !_disposed) {
        notifyListeners();
      }
    }
  }

  Future<List<Chapter>> fetchChapters(String mangaId) async {
    try {
      // Extract MangaDex ID from the full ID
      final String cleanMangaId = mangaId.contains('mangadex')
          ? mangaId.split('mangadex_').last
          : mangaId;

      final url = Uri.parse(
        'https://api.mangadex.org/manga/$cleanMangaId/feed'
        '?translatedLanguage[]=en'
        '&includes[]=scanlation_group'
        '&order[chapter]=desc'
        '&limit=500'
      );

      int maxRetries = 3;
      int currentTry = 0;
      http.Response? response;
      
      while (currentTry < maxRetries) {
        try {
          response = await _client.get(
            url,
            headers: {
              'User-Agent': 'MangaParade/1.0.0',
              'Accept': 'application/json',
            },
          );
          
          if (response.statusCode == 404) {
            return await _fetchChaptersFromFallback(mangaId);
          }
          
          if (response.statusCode != 500) {
            break;
          }
          
          currentTry++;
          if (currentTry < maxRetries) {
            await Future.delayed(Duration(seconds: 1));
          }
        } catch (e) {
          currentTry++;
          if (currentTry < maxRetries) {
            await Future.delayed(Duration(seconds: 1));
          }
        }
      }

      if (response == null || response.statusCode != 200) {
        return await _fetchChaptersFromFallback(mangaId);
      }

      final data = json.decode(response.body);
      if (!data.containsKey('data')) {
        throw Exception('Invalid response format: missing data field');
      }

      final List<dynamic> chapterList = data['data'];
      final chapters = chapterList.map((chapterData) => Chapter.fromJson(chapterData)).toList();
      
      // Sort chapters by volume and chapter number
      chapters.sort((a, b) {
        final volumeCompare = (b.volume ?? '').compareTo(a.volume ?? '');
        if (volumeCompare != 0) return volumeCompare;
        
        final aNum = double.tryParse(a.chapter ?? '') ?? 0;
        final bNum = double.tryParse(b.chapter ?? '') ?? 0;
        return bNum.compareTo(aNum);
      });

      return chapters;
    } catch (e, stackTrace) {
      return await _fetchChaptersFromFallback(mangaId);
    }
  }

  Future<List<Chapter>> _fetchChaptersFromFallback(String mangaId) async {
    try {
      if (mangaId.contains('mangakakalot')) {
        final url = Uri.parse(mangaId.split('mangakakalot_').last);
        final response = await _client.get(
          url,
          headers: {'User-Agent': 'MangaParade/1.0.0'},
        );

        if (response.statusCode != 200) {
          throw Exception('Failed to load chapters from fallback: ${response.statusCode}');
        }

        final document = parser.parse(response.body);
        final chapterElements = document.querySelectorAll('.chapter-list .row');
        final chapters = <Chapter>[];
        var chapterNumber = chapterElements.length;

        for (var element in chapterElements) {
          try {
            final link = element.querySelector('a');
            if (link != null) {
              final title = link.text.trim();
              final chapterUrl = link.attributes['href'] ?? '';
              
              chapters.add(Chapter(
                id: 'mangakakalot_$chapterUrl',
                title: title,
                volume: null,
                chapter: chapterNumber.toString(),
                translatedLanguage: 'en',
                scanlationGroup: null,
                publishAt: DateTime.now(),
                pages: 0,
              ));
              
              chapterNumber--;
            }
          } catch (e) {
          }
        }

        return chapters;
      }
      
      throw Exception('Unsupported manga source');
    } catch (e, stackTrace) {
      throw Exception('Failed to load chapters from all sources');
    }
  }

  Future<void> _saveChapterPagesToCache(String chapterId, MangaPage mangaPage) async {
    try {
      final cacheData = await _getChapterPagesCache();
      
      // Add or update the chapter pages in the cache
      cacheData[chapterId] = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'data': mangaPage.toJson(),
      };
      
      // Limit cache size to 20 most recent chapters
      if (cacheData.length > 20) {
        final sortedEntries = cacheData.entries.toList()
          ..sort((a, b) => (b.value['timestamp'] as int).compareTo(a.value['timestamp'] as int));
        
        cacheData.clear();
        for (var i = 0; i < min(20, sortedEntries.length); i++) {
          cacheData[sortedEntries[i].key] = sortedEntries[i].value;
        }
      }
      
      await _prefs.setString(_chapterPagesCache, json.encode(cacheData));
    } catch (e) {
      // Silently fail if caching doesn't work
      if (kDebugMode) {
        print('Failed to cache chapter pages: $e');
      }
    }
  }

  Future<MangaPage?> _loadChapterPagesFromCache(String chapterId) async {
    try {
      final cacheData = await _getChapterPagesCache();
      
      if (!cacheData.containsKey(chapterId)) {
        return null;
      }
      
      final chapterData = cacheData[chapterId];
      final timestamp = chapterData['timestamp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // Check if cache is still valid (not expired)
      if (now - timestamp > _cacheDuration.inMilliseconds) {
        return null;
      }
      
      return MangaPage.fromJson(chapterData['data']);
    } catch (e) {
      return null;
    }
  }
  
  Future<Map<String, dynamic>> _getChapterPagesCache() async {
    final cacheString = _prefs.getString(_chapterPagesCache);
    if (cacheString == null) {
      return {};
    }
    
    try {
      return json.decode(cacheString) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }

  Future<MangaPage> fetchChapterPages(String chapterId) async {
    try {
      // First check if we have this chapter cached
      final cachedPages = await _loadChapterPagesFromCache(chapterId);
      if (cachedPages != null) {
        return cachedPages;
      }
      
      // If not in cache or cache expired, fetch from API
      final url = Uri.parse('https://api.mangadex.org/at-home/server/$chapterId');
      
      final response = await _client.get(
        url,
        headers: {
          'User-Agent': 'MangaParade/1.0.0',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final mangaPage = MangaPage.fromJson(data);
        
        // Cache the fetched pages
        await _saveChapterPagesToCache(chapterId, mangaPage);
        
        return mangaPage;
      } else {
        throw Exception('Failed to load chapter pages: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    super.dispose();
  }
}
