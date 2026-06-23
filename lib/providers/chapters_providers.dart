import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../models/fs_chapter.dart';

class ChaptersProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // TODO: paste your deployed base URL here
  // Example: https://syncchapterstofirestore-xxxxx-uc.a.run.app
  static const String syncChaptersBaseUrl =
      'https://syncchapterstofirestore-uqirvwodma-uc.a.run.app/';

  // New backend route host for: GET /api/manga/:postId/chapters
  static const String chaptersApiHost =
      'https://us-central1-manga-world-project.cloudfunctions.net';

  Future<void> ensureChaptersIndexed(String mangaId) async {
    final uri = Uri.parse(syncChaptersBaseUrl).replace(queryParameters: {
      'mangaId': mangaId,
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
    bool refresh = false,
  }) async {
    final uri = Uri.parse(chaptersApiHost).replace(
      path: '/api/manga/$postId/chapters',
      queryParameters: {
        'page': '$page',
        'perPage': '$perPage',
        'refresh': refresh ? '1' : '0',
      },
    );

    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('Chapter API failed (${resp.statusCode}): ${resp.body}');
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = (json['data'] as List?) ?? const [];

    final chapters = data.asMap().entries.map((entry) {
      final i = entry.key;
      final ch = (entry.value as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};

      final chapterNumber = (ch['number'] ?? '').toString();
      final title = (ch['title']?.toString().trim().isNotEmpty ?? false)
          ? ch['title'].toString()
          : (chapterNumber.isNotEmpty ? 'Chapter $chapterNumber' : 'Chapter');

      final redirectUrl =
          (ch['mangaPost'] as Map?)?['redirectUrl']?.toString() ?? '';
      final slug = (ch['slug'] ?? '').toString();
      final sourceUrl = redirectUrl.isNotEmpty
          ? redirectUrl
          : (slug.isNotEmpty
              ? 'https://qiscans.org/chapter/$slug'
              : 'https://qiscans.org');

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
