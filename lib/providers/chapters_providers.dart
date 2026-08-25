import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../models/fs_chapter.dart';

class ChaptersProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Keep this for NON-QiScans sources that still use your backend sync path.
  static const String syncChaptersBaseUrl =
      'https://syncchapterstofirestore-uqirvwodma-uc.a.run.app/';

  // QiScans direct API base
  static const String qiscansApiBase = 'https://api.qiscans.org/api/v2';

  Future<void> ensureChaptersIndexed(String mangaId, {bool force = false}) async {
    final uri = Uri.parse(syncChaptersBaseUrl).replace(queryParameters: {
      'mangaId': mangaId,
      if (force) 'force': 'true',
    });

    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception(
        'syncChaptersToFirestore failed: ${resp.statusCode} ${resp.body}',
      );
    }

    // optional: inspect cached vs scraped
    final data = jsonDecode(resp.body);
    if (kDebugMode) {
      debugPrint('ensureChaptersIndexed: $data');
    }
  }

  Future<List<FsChapter>> fetchQiscansChapters(
    int postId, {
    int page = 1,
    int perPage = 200,
    bool refresh = false, // kept for compatibility, not used now
  }) async {
    final uri = Uri.parse('$qiscansApiBase/posts/$postId/chapters').replace(
      queryParameters: {
        'page': '$page',
        'perPage': '$perPage',
        'sortOrder': 'desc',
        'q': '',
      },
    );

    final resp = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json, text/plain, */*',
      },
    );

    final contentType = resp.headers['content-type'] ?? '';
    final bodyLower = resp.body.toLowerCase();

    // Friendly error handling for Cloudflare / HTML challenge pages
    if (resp.statusCode != 200) {
      if (contentType.contains('text/html') ||
          bodyLower.contains('just a moment') ||
          bodyLower.contains('cloudflare') ||
          bodyLower.contains('enable javascript and cookies')) {
        throw Exception(
          'QiScans blocked the chapter request right now. Please try again in a moment.',
        );
      }

      throw Exception(
        'QiScans chapter API failed (${resp.statusCode}): ${resp.body}',
      );
    }

    if (contentType.contains('text/html') ||
        bodyLower.contains('just a moment') ||
        bodyLower.contains('cloudflare') ||
        bodyLower.contains('enable javascript and cookies')) {
      throw Exception(
        'QiScans blocked the chapter request right now. Please try again in a moment.',
      );
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = (json['data'] as List?) ?? const [];

    final chapters = data.asMap().entries.map((entry) {
      final i = entry.key;
      final ch = (entry.value as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};

      final chapterNumber = (ch['number'] ?? '').toString();
      final rawTitle = (ch['title'] ?? '').toString().trim();
      final title = rawTitle.isNotEmpty
          ? rawTitle
          : (chapterNumber.isNotEmpty ? 'Chapter $chapterNumber' : 'Chapter');

      final slug = (ch['slug'] ?? '').toString().trim();

      // Best available readable source URL
      final sourceUrl = slug.isNotEmpty
          ? 'https://qiscans.org/series/placeholder/$slug'
          : 'https://qiscans.org';

      final n = double.tryParse(chapterNumber);
      final index = n != null ? (n * 1000).round() : (1000000 - i);

      DateTime? publishedAt;
      final createdAt = ch['createdAt']?.toString();
      if (createdAt != null && createdAt.isNotEmpty) {
        publishedAt = DateTime.tryParse(createdAt);
      }

      return FsChapter(
        id: (ch['id'] ?? 'qiscans_api_${postId}_$i').toString(),
        title: title,
        chapterNumber: chapterNumber,
        index: index,
        sourceUrl: sourceUrl,
        publishedAt: publishedAt,
      );
    }).toList();

    chapters.sort((a, b) => b.index.compareTo(a.index));
    return chapters;
  }

  Stream<List<FsChapter>> watchChapters(String mangaId) {
    return _db
        .collection('manga')
        .doc(mangaId)
        .collection('chapters')
        .orderBy('index', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(FsChapter.fromDoc).toList());
  }
}
