import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/manga.dart';
import '../models/chapter.dart';

class ReadingHistoryItem {
  final Manga manga;
  final Chapter? lastReadChapter;
  final DateTime lastReadTime;

  ReadingHistoryItem({
    required this.manga,
    this.lastReadChapter,
    required this.lastReadTime,
  });

  Map<String, dynamic> toJson() => {
        'manga': manga.toJson(),
        'lastReadChapter': lastReadChapter?.toJson(),
        'lastReadTime': lastReadTime.toIso8601String(),
      };

  factory ReadingHistoryItem.fromJson(Map<String, dynamic> json) {
    try {
      final mangaJson = json['manga'] as Map<String, dynamic>?;
      final chapterJson = json['lastReadChapter'] as Map<String, dynamic>?;
      final lastReadTimeStr = json['lastReadTime'] as String?;

      if (mangaJson == null) {
        throw FormatException('Missing manga data in reading history item');
      }

      return ReadingHistoryItem(
        manga: Manga.fromJson(mangaJson),
        lastReadChapter: chapterJson != null ? Chapter.fromJson(chapterJson) : null,
        lastReadTime: lastReadTimeStr != null 
            ? DateTime.parse(lastReadTimeStr)
            : DateTime.now(),
      );
    } catch (e, stackTrace) {
      developer.log(
        'Error parsing reading history item: $e\nJSON: $json',
        error: e,
        stackTrace: stackTrace,
      );
      throw FormatException('Failed to parse reading history item: $e');
    }
  }
}

class ReadingHistoryProvider with ChangeNotifier {
  static const _historyKey = 'reading_history';
  final SharedPreferences _prefs;
  List<ReadingHistoryItem> _history = [];
  bool _disposed = false;

  ReadingHistoryProvider({required SharedPreferences prefs}) : _prefs = prefs {
    _loadHistory();
  }

  List<ReadingHistoryItem> get history => List.unmodifiable(_history);

  void _notifyIfNotDisposed() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _loadHistory() {
    final historyJson = _prefs.getStringList(_historyKey) ?? [];
    _history = historyJson
        .map((item) => ReadingHistoryItem.fromJson(jsonDecode(item)))
        .toList();
    _history.sort((a, b) => b.lastReadTime.compareTo(a.lastReadTime));
    _notifyIfNotDisposed();
  }

  void _saveHistory() {
    final historyJson = _history
        .map((item) => jsonEncode(item.toJson()))
        .toList();
    _prefs.setStringList(_historyKey, historyJson);
    _notifyIfNotDisposed();
  }

  void addToHistory(Manga manga, Chapter? chapter) {
    // Remove existing entry if present
    _history.removeWhere((item) => item.manga.id == manga.id);
    
    // Add new entry at the beginning
    _history.insert(
      0,
      ReadingHistoryItem(
        manga: manga,
        lastReadChapter: chapter,
        lastReadTime: DateTime.now(),
      ),
    );

    // Keep only the last 50 items
    if (_history.length > 50) {
      _history = _history.sublist(0, 50);
    }

    _saveHistory();
  }

  void removeFromHistory(String mangaId) {
    _history.removeWhere((item) => item.manga.id == mangaId);
    _saveHistory();
  }

  void clearHistory() {
    _history.clear();
    _saveHistory();
  }
}
