import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/catalog_provider.dart';
import '../providers/favorites_provider.dart';
import '../screens/manga_reader_screen.dart';
import 'manga_card.dart';

class MangaGrid extends StatelessWidget {
  final bool showOnlyFavorites;

  const MangaGrid({
    super.key,
    required this.showOnlyFavorites,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<CatalogProvider>(
      builder: (context, provider, child) {
        final favoritesProvider = context.read<FavoritesProvider>();

        final mangas = showOnlyFavorites
            ? provider.mangas
                .where((manga) => favoritesProvider.isFavorite(manga))
                .toList()
            : provider.mangas;

        // Error state (when you already have items, we still show items)
        if (provider.error != null && mangas.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Error loading manga: ${provider.error}',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => provider.loadPopular(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (mangas.isEmpty && !provider.isLoading) {
          return const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'No manga found',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          );
        }

        // Step 1: No pagination/infinite scroll yet for Firestore.
        return SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.7,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final manga = mangas[index];
              return MangaCard(
                manga: manga,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MangaReaderScreen(manga: manga),
                    ),
                  );
                },
              );
            },
            childCount: mangas.length,
          ),
        );
      },
    );
  }
}
