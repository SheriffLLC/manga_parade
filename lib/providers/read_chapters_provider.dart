import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chapter.dart';

class ReadChaptersProvider with ChangeNotifier {
  final SharedPreferences prefs;
  final Set<String> _readChapters = {};
  static const String _readChaptersKey = 'read_chapters';
  bool _disposed = false;

  ReadChaptersProvider({required this.prefs}) {
    _loadReadChapters();
  }

  bool isChapterRead(String chapterId) => _readChapters.contains(chapterId);

  void markChapterAsRead(String chapterId) {
    if (!_readChapters.contains(chapterId)) {
      _readChapters.add(chapterId);
      _saveReadChapters();
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  void markChapterAsUnread(String chapterId) {
    if (_readChapters.contains(chapterId)) {
      _readChapters.remove(chapterId);
      _saveReadChapters();
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  void _loadReadChapters() {
    final readChaptersJson = prefs.getStringList(_readChaptersKey);
    if (readChaptersJson != null) {
      _readChapters.addAll(readChaptersJson);
    }
  }

  Future<void> _saveReadChapters() async {
    await prefs.setStringList(_readChaptersKey, _readChapters.toList());
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
