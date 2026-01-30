import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fs_chapter.dart';

class ChaptersProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
