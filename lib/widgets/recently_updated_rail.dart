import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/catalog_provider.dart';
import '../screens/view_all_screen.dart';
import 'rail_manga_card.dart';

class RecentlyUpdatedRail extends StatelessWidget {
  const RecentlyUpdatedRail({super.key});

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    final cardWidth = isTablet ? 190.0 : 160.0;
    final railHeight = isTablet ? 280.0 : 240.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Builder(
          builder: (context) {
            final catalog = context.watch<CatalogProvider>();

            if (catalog.isLoadingRecentlyUpdated &&
                catalog.recentlyUpdated.isEmpty) {
              return const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (catalog.recentlyUpdatedError != null &&
                catalog.recentlyUpdated.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  catalog.recentlyUpdatedError!,
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }

            final items = catalog.recentlyUpdated;
            if (items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'No recent updates yet.',
                  style: TextStyle(color: Colors.white70),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Recently Updated',
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
                                type: ViewAllType.recentlyUpdated,
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
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final m = items[i];
                      return SizedBox(
                        width: cardWidth,
                        child: RailMangaCard(manga: m),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
