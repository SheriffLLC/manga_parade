import 'package:flutter/material.dart';
import '../widgets/continue_reading_grid.dart';
import '../widgets/recently_updated_rail.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: const [
        SizedBox(height: 8),

        // Keep Continue Reading first
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            'Continue Reading',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        ContinueReadingGrid(),

        // Rail should appear even if ContinueReadingGrid is empty
        SizedBox(height: 12),
        RecentlyUpdatedRail(),
      ],
    );
  }
}
