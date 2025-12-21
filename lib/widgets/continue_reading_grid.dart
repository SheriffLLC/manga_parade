import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/reading_history_provider.dart';
import '../models/manga.dart';
import 'manga_card.dart';

class ContinueReadingGrid extends StatelessWidget {
  const ContinueReadingGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ReadingHistoryProvider>(
      builder: (context, historyProvider, child) {
        final history = historyProvider.history;
        
        if (history.isEmpty) {
          return const Center(
            child: Text(
              'No reading history yet.\nStart reading some manga!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.7,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: history.length,
          itemBuilder: (context, index) {
            final item = history[index];
            return MangaCard(
              manga: item.manga,
              subtitle: item.lastReadChapter != null
                  ? 'Last read: ${item.lastReadChapter!.title}'
                  : null,
            );
          },
        );
      },
    );
  }
}
