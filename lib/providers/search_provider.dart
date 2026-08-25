import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/manga.dart';
import '../services/mangakakalot_service.dart';

class SearchProvider with ChangeNotifier {
  final MangaKakalotService _mangakakalotService;
  
  SearchProvider(this._mangakakalotService);
  
  List<Manga> _searchResults = [];
  String? _selectedGenre;
  bool _isSearching = false;
  bool _isLoadingMore = false;
  String? _error;
  bool _hasMoreResults = true;
  String _selectedSource = 'all';
  
  static const List<String> availableGenres = [
    'Action', 'Adventure', 'Comedy', 'Drama', 'Fantasy', 
    'Horror', 'Romance', 'School Life', 'Sci-fi', 'Slice of Life',
    'Sports', 'Supernatural'
  ];

  List<Manga> get searchResults => _searchResults;
  String? get selectedGenre => _selectedGenre;
  bool get isSearching => _isSearching;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get hasMoreResults => _hasMoreResults;
  String get selectedSource => _selectedSource;

  void setSourceFilter(String source) {
    if (_selectedSource == source) return;
    _selectedSource = source;
    notifyListeners();
  }

  void _setSearching(bool value) {
    if (_isSearching != value) {
      _isSearching = value;
      notifyListeners();
    }
  }

  void _setLoadingMore(bool value) {
    if (_isLoadingMore != value) {
      _isLoadingMore = value;
      notifyListeners();
    }
  }

  void setSelectedGenre(String? genre) {
    if (_selectedGenre == genre) {
      // If the same genre is selected again, deselect it
      _selectedGenre = null;
      _searchResults = [];
      _error = null;
      _hasMoreResults = true;
      notifyListeners();
      return;
    }
    
    _selectedGenre = genre;
    _hasMoreResults = true;
    
    if (genre != null && genre.isNotEmpty) {
      searchByGenre(genre, refresh: true);
    } else {
      _searchResults = [];
      _error = null;
      notifyListeners();
    }
  }

  Future<void> searchByGenre(String genre, {bool refresh = false, bool loadMore = false}) async {
    try {
      if (refresh) {
        _hasMoreResults = true;
        _searchResults = [];
      } else if (loadMore) {
        if (!_hasMoreResults) return;
      }
      
      _setSearching(true);
      _setLoadingMore(loadMore);
      
      _error = null;
      
      if (refresh) {
        // Clear previous results immediately to show loading state
        notifyListeners();
      }
      
      // Get manga for this genre
      final List<Manga> mangas = await _mangakakalotService.fetchMangaByGenre(genre);
      
      // Since we're using fallback data, we'll just show all results at once
      // and disable pagination to avoid confusion
      _hasMoreResults = false;
      
      if (refresh) {
        _searchResults = mangas;
      } else if (loadMore) {
        // We won't actually load more since we're showing all results at once
        // But we'll keep this logic in case we switch back to pagination later
        _searchResults.addAll(mangas);
      }
      
      _selectedGenre = genre;
    } catch (e) {
      _error = 'Failed to load manga for genre: $genre. ${e.toString()}';
      debugPrint('Error in searchByGenre: $e');
    } finally {
      _setSearching(false);
      _setLoadingMore(false);
      notifyListeners();
    }
  }

  Future<void> loadMoreGenreResults() async {
    if (_selectedGenre != null && _hasMoreResults && !_isLoadingMore) {
      await searchByGenre(_selectedGenre!, loadMore: true);
    }
  }

  Future<void> search(String query) async {
    if (query.isEmpty) {
      if (_selectedGenre != null && _selectedGenre!.isNotEmpty) {
        // If a genre is selected but query is empty, keep showing genre results
        return;
      }
      _searchResults = [];
      _error = null;
      notifyListeners();
      return;
    }

    try {
      _setSearching(true);
      _error = null;

      List<Manga> apiResults = [];
      List<Manga> firestoreResults = [];

      // 1. Fetch from MangaDex API if source is 'all' or 'mangadex'
      if (_selectedSource == 'all' || _selectedSource == 'mangadex') {
        final url = Uri.parse(
          'https://api.mangadex.org/manga'
          '?title=$query'
          '&limit=20'
          '&includes[]=cover_art'
          '&contentRating[]=safe'
          '&contentRating[]=suggestive'
          '&availableTranslatedLanguage[]=en'
          '&order[relevance]=desc'
        );

        final response = await http.Client().get(
          url,
          headers: {
            'User-Agent': 'MangaParade/1.0.0',
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data.containsKey('data')) {
            final List<dynamic> mangaList = data['data'];
            apiResults = mangaList.map((mangaData) {
              try {
                return Manga.fromJson(mangaData);
              } catch (e) {
                return null;
              }
            }).whereType<Manga>().toList();
          }
        } else {
          debugPrint('MangaDex API search failed: ${response.statusCode}');
        }
      }

      // 2. Fetch from Firestore if source is not 'mangadex'
      if (_selectedSource != 'mangadex') {
        firestoreResults = await _searchFirestore(query, source: _selectedSource);
      }

      // 3. Combine results
      // Sort Firestore results to show first, followed by MangaDex remote results
      _searchResults = [...firestoreResults, ...apiResults];
      _error = null;
    } catch (e) {
      _error = 'Error searching manga: $e';
      _searchResults = [];
    } finally {
      _setSearching(false);
    }
  }

  Future<List<Manga>> _searchFirestore(String query, {String? source}) async {
    try {
      final db = FirebaseFirestore.instance;
      Query<Map<String, dynamic>> baseQuery = db.collection('manga');
      if (source != null && source != 'all') {
        baseQuery = baseQuery.where('source', isEqualTo: source);
      } else {
        // For 'all' search source, we search for non-mangadex titles from firestore
        // because mangadex is already searched via API.
        baseQuery = baseQuery.where('source', isNotEqualTo: 'mangadex');
      }

      final snap = await baseQuery.get();
      final results = <Manga>[];
      final queryLower = query.toLowerCase();

      for (final doc in snap.docs) {
        final data = doc.data();
        final title = (data['title'] as String?)?.toLowerCase() ?? '';
        final desc = (data['description'] as String?)?.toLowerCase() ?? '';

        if (title.contains(queryLower) || desc.contains(queryLower)) {
          // Clean the cover url if needed
          final map = {
            ...data,
            'id': doc.id,
          };
          results.add(Manga.fromJson(map));
        }
      }
      return results;
    } catch (e) {
      debugPrint('Firestore search error: $e');
      return [];
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
