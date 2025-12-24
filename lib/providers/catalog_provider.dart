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
    } catch (e) {
      _recentlyUpdatedError = 'Failed to load Recently Updated: $e';
      debugPrint(_recentlyUpdatedError);
    } finally {
      _isLoadingRecentlyUpdated = false;
      notifyListeners();
    }
  }

  // -----------------------------
  // REFRESH HOME
  // -----------------------------
  Future<void> refreshHome() async {
    _mangas.clear();
    _recentlyUpdated.clear();
    _lastDoc = null;
    _hasMore = true;

    await Future.wait([
      loadRecentlyUpdated(),
      fetchNextPage(),
    ]);
  }
}
