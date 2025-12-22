import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/manga.dart';

class CatalogProvider extends ChangeNotifier {
  CatalogProvider({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  final List<Manga> _mangas = [];
  bool _isLoading = false;
  bool _hasMore = true;

  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;

  String? _error;

  List<Manga> get mangas => List.unmodifiable(_mangas);
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  String? get error => _error;

  static const int _defaultPageSize = 30;

  /// Call this once when the app starts OR when user pulls to refresh.
  Future<void> refresh({int pageSize = _defaultPageSize}) async {
    _mangas.clear();
    _lastDoc = null;
    _hasMore = true;
    _error = null;
    notifyListeners();

    await fetchNextPage(pageSize: pageSize);
  }

  /// Call this when user scrolls near the bottom.
  Future<void> fetchNextPage({int pageSize = _defaultPageSize}) async {
    if (_isLoading || !_hasMore) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      developer.log('[CatalogProvider] Fetching page...');

      Query<Map<String, dynamic>> query = _db
          .collection('manga')
          .orderBy('catalogScore', descending: true)
          .limit(pageSize);

      if (_lastDoc != null) {
        query = query.startAfterDocument(_lastDoc!);
      }

      final snap = await query.get();

      developer.log('[CatalogProvider] Got ${snap.docs.length} docs');

      if (snap.docs.isEmpty) {
        _hasMore = false;
        return;
      }

      _lastDoc = snap.docs.last;

      final newItems = <Manga>[];

      for (final doc in snap.docs) {
        final data = doc.data();

        // Ensure unique id (your docs don't have an id field)
        final withId = <String, dynamic>{
          ...data,
          'id': data['id'] ?? doc.id,
        };

        try {
          newItems.add(Manga.fromJson(withId));
        } catch (e, st) {
          developer.log(
            '[CatalogProvider] Failed to parse ${doc.id}: $e',
            error: e,
            stackTrace: st,
          );
        }
      }

      // Avoid duplicates if refresh + pagination overlaps
      final existingIds = _mangas.map((m) => m.id).toSet();
      for (final m in newItems) {
        if (!existingIds.contains(m.id)) {
          _mangas.add(m);
        }
      }

      // If we got fewer than requested, we’re probably at the end
      if (snap.docs.length < pageSize) {
        _hasMore = false;
      }

      developer.log(
        '[CatalogProvider] Total items now: ${_mangas.length}, hasMore=$_hasMore',
      );
    } catch (e, st) {
      developer.log('[CatalogProvider] Query failed: $e',
          error: e, stackTrace: st);
      _error = 'Failed to load catalog: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
