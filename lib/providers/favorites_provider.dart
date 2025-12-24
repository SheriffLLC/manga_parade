import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/manga.dart';

class FavoritesProvider extends ChangeNotifier {
  final SharedPreferences _prefs;
  static const _key = 'favorite_ids';

  late Set<String> _favoriteIds;

  FavoritesProvider({required SharedPreferences prefs}) : _prefs = prefs {
    _favoriteIds = _prefs.getStringList(_key)?.toSet() ?? <String>{};
  }

  bool isFavorite(Manga manga) => _favoriteIds.contains(manga.id);

  void toggleFavorite(Manga manga) {
    if (_favoriteIds.contains(manga.id)) {
      _favoriteIds.remove(manga.id);
    } else {
      _favoriteIds.add(manga.id);
    }
    _prefs.setStringList(_key, _favoriteIds.toList());
    notifyListeners();
  }
}
