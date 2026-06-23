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

  List<Manga> get mangas => List.unmodifiable(_mangas);
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  String? get error => _error;

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

  List<Manga> _deduplicateMangas(List<Manga> list) {
    final Map<String, Manga> unique = {};
    for (final manga in list) {
      final norm = manga.title
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '')
          .trim();
      final existing = unique[norm];
      if (existing == null) {
        unique[norm] = manga;
      } else {
        // Merge the two Manga objects: prefer 'mangadex' over redirect-only sources
        final preferNew = manga.source == 'mangadex' && existing.source != 'mangadex';
        final merged = Manga(
          id: preferNew ? manga.id : existing.id,
          title: preferNew ? manga.title : existing.title,
          coverUrl: preferNew ? manga.coverUrl : existing.coverUrl,
          description: preferNew
              ? (manga.description.isNotEmpty ? manga.description : existing.description)
              : (existing.description.isNotEmpty ? existing.description : manga.description),
          genres: preferNew ? manga.genres : existing.genres,
          catalogScore: (manga.catalogScore ?? 0) > (existing.catalogScore ?? 0)
              ? manga.catalogScore
              : existing.catalogScore,
          createdAt: existing.createdAt ?? manga.createdAt,
          updatedAt: (manga.updatedAt != null && existing.updatedAt != null)
              ? (manga.updatedAt!.isAfter(existing.updatedAt!) ? manga.updatedAt : existing.updatedAt)
              : (existing.updatedAt ?? manga.updatedAt),
          volumes: preferNew ? manga.volumes : existing.volumes,
          chapters: preferNew ? manga.chapters : existing.chapters,
          source: preferNew ? manga.source : existing.source,
          sourceUrl: preferNew ? manga.sourceUrl : existing.sourceUrl,
          qiscansSourceUrl: manga.qiscansSourceUrl ?? existing.qiscansSourceUrl,
          asurascansSourceUrl: manga.asurascansSourceUrl ?? existing.asurascansSourceUrl,
          qiscansPostId: manga.qiscansPostId ?? existing.qiscansPostId,
        );
        unique[norm] = merged;
      }
    }
    
    // Stable sort: Prioritize in-app readable titles (MangaDex) first
    final result = unique.values.toList();
    final inApp = result.where((m) => m.source == 'mangadex').toList();
    final redirectOnly = result.where((m) => m.source != 'mangadex').toList();
    return [...inApp, ...redirectOnly];
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
      Query<Map<String, dynamic>> query = _db
          .collection('manga')
          .orderBy('catalogScore', descending: true)
          .limit(pageSize);

      if (_lastDoc != null) {
        query = query.startAfterDocument(_lastDoc!);
      }

      final snap = await query.get();

      if (snap.docs.isNotEmpty) {
        _lastDoc = snap.docs.last;

        for (final doc in snap.docs) {
          final map = _withDocIdAndCleanUrl(doc);
          _mangas.add(Manga.fromJson(map));
        }

        final deduped = _deduplicateMangas(_mangas);
        _mangas.clear();
        _mangas.addAll(deduped);
      }

      if (snap.docs.length < pageSize) {
        _hasMore = false;
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
      final snap = await _db
          .collection('manga')
          .orderBy('updatedAt', descending: true)
          .limit(limit)
          .get();

      _recentlyUpdated
        ..clear()
        ..addAll(
            snap.docs.map((d) => Manga.fromJson(_withDocIdAndCleanUrl(d))));
      final deduped = _deduplicateMangas(_recentlyUpdated);
      _recentlyUpdated.clear();
      _recentlyUpdated.addAll(deduped);
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
      final snap = await _db
          .collection('manga')
          .orderBy('catalogScore', descending: true)
          .limit(limit)
          .get();

      _mostPopular
        ..clear()
        ..addAll(
            snap.docs.map((d) => Manga.fromJson(_withDocIdAndCleanUrl(d))));
      final deduped = _deduplicateMangas(_mostPopular);
      _mostPopular.clear();
      _mostPopular.addAll(deduped);
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
        final deduped = _deduplicateMangas(_recentlyUpdatedAll);
        _recentlyUpdatedAll.clear();
        _recentlyUpdatedAll.addAll(deduped);
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
        final deduped = _deduplicateMangas(_mostPopularAll);
        _mostPopularAll.clear();
        _mostPopularAll.addAll(deduped);
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

    await Future.wait([
      loadRecentlyUpdated(),
      loadMostPopular(),
      fetchNextPage(),
    ]);
  }
}
