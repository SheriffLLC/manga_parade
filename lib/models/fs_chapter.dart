import 'package:cloud_firestore/cloud_firestore.dart';

class FsChapter {
  final String id; // doc id
  final String title;
  final String chapterNumber;
  final int index; // used for sorting
  final String sourceUrl;
  final DateTime? publishedAt;

  FsChapter({
    required this.id,
    required this.title,
    required this.chapterNumber,
    required this.index,
    required this.sourceUrl,
    this.publishedAt,
  });

  factory FsChapter.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    DateTime? toDate(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      return null;
    }

    return FsChapter(
      id: doc.id,
      title: (data['title'] ?? 'Chapter').toString(),
      chapterNumber: (data['chapterNumber'] ?? '').toString(),
      index: (data['index'] is num) ? (data['index'] as num).toInt() : 0,
      sourceUrl: (data['sourceUrl'] ?? '').toString(),
      publishedAt: toDate(data['publishedAt']),
    );
  }
}
