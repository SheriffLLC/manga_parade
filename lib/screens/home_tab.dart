import 'package:flutter/material.dart';
import '../widgets/continue_reading_grid.dart';
import '../widgets/most_popular_rail.dart';
import '../widgets/recently_updated_rail.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: const [
        SizedBox(height: 8),

        ContinueReadingRail(),

        RecentlyUpdatedRail(),

        SizedBox(height: 12),
        MostPopularRail(),
      ],
    );
  }
}
