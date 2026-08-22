import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/reading_history_provider.dart';
import '../screens/view_all_screen.dart';
import 'rail_manga_card.dart';

class ContinueReadingRail extends StatelessWidget {
  const ContinueReadingRail({super.key});

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    final cardWidth = isTablet ? 190.0 : 160.0;
    final railHeight = isTablet ? 280.0 : 240.0;

    return Consumer<ReadingHistoryProvider>(
      builder: (context, historyProvider, child) {
        final history = historyProvider.history;

        if (history.isEmpty) {
          return const SizedBox.shrink();
        }

        // Limit rail to top 10 items
        final displayItems = history.take(10).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Continue Reading',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ViewAllScreen(
                            type: ViewAllType.continueReading,
                          ),
                        ),
                      );
                    },
                    child: const Text('View all'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: railHeight,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: displayItems.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final item = displayItems[index];
                  final displaySubtitle = item.lastReadChapter != null
                      ? 'Ch. ${item.lastReadChapter!.title}'
                      : null;

                  return SizedBox(
                    width: cardWidth,
                    child: RailMangaCard(
                      manga: item.manga,
                      subtitle: displaySubtitle,
                      heroPrefix: 'continue_',
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}
