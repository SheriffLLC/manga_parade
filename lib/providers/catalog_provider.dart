import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/manga.dart';

class CatalogProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // -----------------------------
  // ALL MANGA (paginated grid)
  // -----------------------------
  final List<Manga> _mangas = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  String _selectedSource = 'all';
  bool _fetchingMangaDex = true;

  List<Manga> get mangas => List.unmodifiable(_mangas);
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  String? get error => _error;
  String get selectedSource => _selectedSource;

  void setSourceFilter(String source) {
    if (_selectedSource == source) return;
    _selectedSource = source;
    _mangas.clear();
    _lastDoc = null;
    _hasMore = true;
    _fetchingMangaDex = (source == 'all' || source == 'mangadex');
    notifyListeners();
    fetchNextPage();
  }

  // -----------------------------
  // RECENTLY UPDATED (rail)
  // -----------------------------
  final List<Manga> _recentlyUpdated = [];
  bool _isLoadingRecentlyUpdated = false;
  String? _recentlyUpdatedError;

  List<Manga> get recentlyUpdated => List.unmodifiable(_recentlyUpdated);
  bool get isLoadingRecentlyUpdated => _isLoadingRecentlyUpdated;
  String? get recentlyUpdatedError => _recentlyUpdatedError;

  // Keep your UI calls working
  Future<void> refresh() => refreshHome();

  Map<String, dynamic> _withDocIdAndCleanUrl(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();

    String clean(String? url) {
      if (url == null) return '';
      final u = url.trim().replaceAll(RegExp(r'^"+|"+$'), '');

      // If it's a Next.js _next/image wrapper, try to extract the real url= param
      if (u.contains('/_next/image') && u.contains('url=')) {
        final uri = Uri.tryParse(u);
        final raw = uri?.queryParameters['url'];
        if (raw != null && raw.isNotEmpty) {
          return Uri.decodeComponent(raw);
        }
      }

      return u;
    }

    return {
      ...data,
      'id': doc.id,
      'coverUrl': clean(data['coverUrl'] as String?),
    };
  }

  // -----------------------------
  // PAGINATED FETCH (All Manga)
  // -----------------------------
  Future<void> fetchNextPage({int pageSize = 24}) async {
    if (_isLoading || !_hasMore) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      int fetchedCount = 0;
      bool hasMoreInQuery = true;

      while (fetchedCount < pageSize && hasMoreInQuery) {
        Query<Map<String, dynamic>> query;
        final int limitAmount = pageSize - fetchedCount;

        if (_selectedSource != 'all') {
          query = _db
              .collection('manga')
              .where('source', isEqualTo: _selectedSource)
              .orderBy('catalogScore', descending: true)
              .limit(limitAmount);
        } else {
          if (_fetchingMangaDex) {
            query = _db
                .collection('manga')
                .where('source', isEqualTo: 'mangadex')
                .orderBy('catalogScore', descending: true)
                .limit(limitAmount);
          } else {
            query = _db
                .collection('manga')
                .orderBy('catalogScore', descending: true)
                .limit(limitAmount);
          }
        }

        if (_lastDoc != null) {
          query = query.startAfterDocument(_lastDoc!);
        }

        final snap = await query.get();

        if (snap.docs.isEmpty) {
          hasMoreInQuery = false;
        } else {
          _lastDoc = snap.docs.last;

          for (final doc in snap.docs) {
            final data = doc.data();
            final source = (data['source'] as String?)?.toLowerCase();

            if (_selectedSource != 'all') {
              final map = _withDocIdAndCleanUrl(doc);
              _mangas.add(Manga.fromJson(map));
              fetchedCount++;
            } else {
              if (_fetchingMangaDex) {
                final map = _withDocIdAndCleanUrl(doc);
                _mangas.add(Manga.fromJson(map));
                fetchedCount++;
              } else {
                // Non-MangaDex title
                if (source != 'mangadex') {
                  final map = _withDocIdAndCleanUrl(doc);
                  _mangas.add(Manga.fromJson(map));
                  fetchedCount++;
                }
              }
            }
          }
        }

        if (snap.docs.length < limitAmount) {
          if (_selectedSource == 'all' && _fetchingMangaDex) {
            _fetchingMangaDex = false;
            _lastDoc = null; // Reset pagination cursor
          } else {
            hasMoreInQuery = false;
            _hasMore = false;
          }
        }
      }
    } catch (e) {
      _error = 'Failed to load manga catalog: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // -----------------------------
  // RECENTLY UPDATED (no paging)
  // -----------------------------
  Future<void> loadRecentlyUpdated({int limit = 20}) async {
    if (_isLoadingRecentlyUpdated) return;

    _isLoadingRecentlyUpdated = true;
    _recentlyUpdatedError = null;
    notifyListeners();

    try {
      // 1. Fetch MangaDex recently updated (fetch 60 to filter for chapters in memory)
      final mdSnap = await _db
          .collection('manga')
          .where('source', isEqualTo: 'mangadex')
          .orderBy('updatedAt', descending: true)
          .limit(60)
          .get();

      // 2. Fetch all recently updated (to extract non-MangaDex)
      final allSnap = await _db
          .collection('manga')
          .orderBy('updatedAt', descending: true)
          .limit(limit * 2)
          .get();

      final mangadex = mdSnap.docs
          .map((d) => Manga.fromJson(_withDocIdAndCleanUrl(d)))
          .where((m) => (m.chaptersCount ?? 0) > 0)
          .take(limit)
          .toList();

      final others = allSnap.docs
          .map((d) => Manga.fromJson(_withDocIdAndCleanUrl(d)))
          .where((m) => m.source?.toLowerCase() != 'mangadex')
          .toList();

      final combined = [...mangadex, ...others];
      if (combined.length > limit) {
        combined.removeRange(limit, combined.length);
      }

      _recentlyUpdated
        ..clear()
        ..addAll(combined);
    } catch (e) {
      _recentlyUpdatedError = 'Failed to load Recently Updated: $e';
      debugPrint(_recentlyUpdatedError);
    } finally {
      _isLoadingRecentlyUpdated = false;
      notifyListeners();
    }
  }

  // -----------------------------
  // MOST POPULAR (rail)
  // -----------------------------
  final List<Manga> _mostPopular = [];
  bool _isLoadingMostPopular = false;
  String? _mostPopularError;

  List<Manga> get mostPopular => List.unmodifiable(_mostPopular);
  bool get isLoadingMostPopular => _isLoadingMostPopular;
  String? get mostPopularError => _mostPopularError;

  Future<void> loadPopular({int limit = 20}) => loadMostPopular(limit: limit);

  Future<void> loadMostPopular({int limit = 20}) async {
    if (_isLoadingMostPopular) return;

    _isLoadingMostPopular = true;
    _mostPopularError = null;
    notifyListeners();

    try {
      // 1. Fetch MangaDex recently updated pool (fetch 100 to filter and shuffle)
      final mdSnap = await _db
          .collection('manga')
          .where('source', isEqualTo: 'mangadex')
          .orderBy('updatedAt', descending: true)
          .limit(100)
          .get();

      // 2. Fetch popular non-MangaDex
      final allSnap = await _db
          .collection('manga')
          .orderBy('catalogScore', descending: true)
          .limit(limit * 2)
          .get();

      final mangadexWithChapters = mdSnap.docs
          .map((d) => Manga.fromJson(_withDocIdAndCleanUrl(d)))
          .where((m) => (m.chaptersCount ?? 0) > 0)
          .toList();

      mangadexWithChapters.shuffle(); // Randomized recs pool
      final mangadex = mangadexWithChapters.take(limit).toList();

      final others = allSnap.docs
          .map((d) => Manga.fromJson(_withDocIdAndCleanUrl(d)))
          .where((m) => m.source?.toLowerCase() != 'mangadex')
          .toList();

      final combined = [...mangadex, ...others];
      if (combined.length > limit) {
        combined.removeRange(limit, combined.length);
      }

      _mostPopular
        ..clear()
        ..addAll(combined);
    } catch (e) {
      _mostPopularError = 'Failed to load Most Popular: $e';
    } finally {
      _isLoadingMostPopular = false;
      notifyListeners();
    }
  }

  // -----------------------------
  // VIEW ALL: RECENTLY UPDATED (paginated)
  // -----------------------------
  final List<Manga> _recentlyUpdatedAll = [];
  DocumentSnapshot<Map<String, dynamic>>? _recentlyUpdatedAllLastDoc;
  bool _isLoadingRecentlyUpdatedAll = false;
  bool _hasMoreRecentlyUpdatedAll = true;
  String? _recentlyUpdatedAllError;

  List<Manga> get recentlyUpdatedAll => List.unmodifiable(_recentlyUpdatedAll);
  bool get isLoadingRecentlyUpdatedAll => _isLoadingRecentlyUpdatedAll;
  bool get hasMoreRecentlyUpdatedAll => _hasMoreRecentlyUpdatedAll;
  String? get recentlyUpdatedAllError => _recentlyUpdatedAllError;

  Future<void> resetRecentlyUpdatedAll() async {
    _recentlyUpdatedAll.clear();
    _recentlyUpdatedAllLastDoc = null;
    _hasMoreRecentlyUpdatedAll = true;
    _recentlyUpdatedAllError = null;
    notifyListeners();
    await fetchNextRecentlyUpdatedAllPage();
  }

  Future<void> fetchNextRecentlyUpdatedAllPage({int pageSize = 30}) async {
    if (_isLoadingRecentlyUpdatedAll || !_hasMoreRecentlyUpdatedAll) return;

    _isLoadingRecentlyUpdatedAll = true;
    _recentlyUpdatedAllError = null;
    notifyListeners();

    try {
      Query<Map<String, dynamic>> q = _db
          .collection('manga')
          .orderBy('updatedAt', descending: true)
          .limit(pageSize);

      if (_recentlyUpdatedAllLastDoc != null) {
        q = q.startAfterDocument(_recentlyUpdatedAllLastDoc!);
      }

      final snap = await q.get();
      if (snap.docs.isNotEmpty) {
        _recentlyUpdatedAllLastDoc = snap.docs.last;
        for (final doc in snap.docs) {
          _recentlyUpdatedAll.add(Manga.fromJson(_withDocIdAndCleanUrl(doc)));
        }
      }

      if (snap.docs.length < pageSize) {
        _hasMoreRecentlyUpdatedAll = false;
      }
    } catch (e) {
      _recentlyUpdatedAllError = 'Failed to load Recently Updated: $e';
    } finally {
      _isLoadingRecentlyUpdatedAll = false;
      notifyListeners();
    }
  }

  // -----------------------------
  // VIEW ALL: MOST POPULAR (paginated)
  // -----------------------------
  final List<Manga> _mostPopularAll = [];
  DocumentSnapshot<Map<String, dynamic>>? _mostPopularAllLastDoc;
  bool _isLoadingMostPopularAll = false;
  bool _hasMoreMostPopularAll = true;
  String? _mostPopularAllError;

  List<Manga> get mostPopularAll => List.unmodifiable(_mostPopularAll);
  bool get isLoadingMostPopularAll => _isLoadingMostPopularAll;
  bool get hasMoreMostPopularAll => _hasMoreMostPopularAll;
  String? get mostPopularAllError => _mostPopularAllError;

  Future<void> resetMostPopularAll() async {
    _mostPopularAll.clear();
    _mostPopularAllLastDoc = null;
    _hasMoreMostPopularAll = true;
    _mostPopularAllError = null;
    notifyListeners();
    await fetchNextMostPopularAllPage();
  }

  Future<void> fetchNextMostPopularAllPage({int pageSize = 30}) async {
    if (_isLoadingMostPopularAll || !_hasMoreMostPopularAll) return;

    _isLoadingMostPopularAll = true;
    _mostPopularAllError = null;
    notifyListeners();

    try {
      Query<Map<String, dynamic>> q = _db
          .collection('manga')
          .orderBy('catalogScore', descending: true)
          .limit(pageSize);

      if (_mostPopularAllLastDoc != null) {
        q = q.startAfterDocument(_mostPopularAllLastDoc!);
      }

      final snap = await q.get();
      if (snap.docs.isNotEmpty) {
        _mostPopularAllLastDoc = snap.docs.last;
        for (final doc in snap.docs) {
          _mostPopularAll.add(Manga.fromJson(_withDocIdAndCleanUrl(doc)));
        }
      }

      if (snap.docs.length < pageSize) {
        _hasMoreMostPopularAll = false;
      }
    } catch (e) {
      _mostPopularAllError = 'Failed to load Most Popular: $e';
    } finally {
      _isLoadingMostPopularAll = false;
      notifyListeners();
    }
  }

  // -----------------------------
  // REFRESH HOME
  // -----------------------------
  Future<void> refreshHome() async {
    _mangas.clear();
    _recentlyUpdated.clear();
    _mostPopular.clear();
    _lastDoc = null;
    _hasMore = true;
    _fetchingMangaDex = (_selectedSource == 'all' || _selectedSource == 'mangadex');

    await Future.wait([
      loadRecentlyUpdated(),
      loadMostPopular(),
      fetchNextPage(),
    ]);
  }
}
