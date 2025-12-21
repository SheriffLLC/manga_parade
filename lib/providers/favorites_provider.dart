import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/manga.dart';

class FavoritesProvider extends ChangeNotifier {
  final Map<String, Manga> _favoriteManga = {};
  final SharedPreferences _prefs;
  bool _disposed = false;

  FavoritesProvider({required SharedPreferences prefs}) : _prefs = prefs {
    _loadFavorites();
  }

  List<Manga> get favorites => _favoriteManga.values.toList();

  bool isFavorite(Manga manga) => _favoriteManga.containsKey(manga.id);

  void addFavorite(Manga manga) {
    if (!_favoriteManga.containsKey(manga.id)) {
      _favoriteManga[manga.id] = manga;
      _saveFavorites();
    }
  }

  void removeFavorite(Manga manga) {
    if (_favoriteManga.containsKey(manga.id)) {
      _favoriteManga.remove(manga.id);
      _saveFavorites();
    }
  }

  void _loadFavorites() {
    try {
      final favoritesJson = _prefs.getStringList('favorites') ?? [];
      _favoriteManga.clear();
      for (final json in favoritesJson) {
        final mangaMap = jsonDecode(json) as Map<String, dynamic>;
        final manga = Manga.fromJson(mangaMap);
        _favoriteManga[manga.id] = manga;
      }
      if (!_disposed) notifyListeners();
    } catch (e) {
    }
  }

  void _saveFavorites() {
    try {
      final favoritesJson = _favoriteManga.values
          .map((manga) => jsonEncode(manga.toJson()))
          .toList();
      _prefs.setStringList('favorites', favoritesJson);
      if (!_disposed) notifyListeners();
    } catch (e) {
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
