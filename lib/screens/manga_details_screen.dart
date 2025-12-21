import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/manga.dart';
import '../providers/favorites_provider.dart';
import '../widgets/manga_image.dart';

class MangaDetailsScreen extends StatelessWidget {
  final Manga manga;

  const MangaDetailsScreen({super.key, required this.manga});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(manga.title),
        actions: [
          Consumer<FavoritesProvider>(
            builder: (context, favoritesProvider, child) {
              final isFavorite = favoritesProvider.isFavorite(manga);
              return IconButton(
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite ? Colors.red : null,
                ),
                onPressed: () {
                  if (isFavorite) {
                    favoritesProvider.removeFavorite(manga);
                  } else {
                    favoritesProvider.addFavorite(manga);
                  }
                },
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'manga_cover_${manga.id}',
              child: MangaImage(
                imageUrl: manga.coverUrl,
                height: 300,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    manga.title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  if (manga.description.isNotEmpty) ...[
                    Text(
                      'Description:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(manga.description),
                    const SizedBox(height: 16),
                  ],
                  // Display volume and chapter information if available
                  Row(
                    children: [
                      if (manga.volumes != null) ...[
                        Expanded(
                          child: Card(
                            color: Theme.of(context).primaryColor.withOpacity(0.1),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                children: [
                                  const Icon(Icons.book, size: 28),
                                  const SizedBox(height: 4),
                                  const Text('Volumes', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text(manga.volumes ?? 'Unknown'),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (manga.chapters != null) ...[
                        Expanded(
                          child: Card(
                            color: Theme.of(context).primaryColor.withOpacity(0.1),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                children: [
                                  const Icon(Icons.menu_book, size: 28),
                                  const SizedBox(height: 4),
                                  const Text('Chapters', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text(manga.chapters ?? 'Unknown'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (manga.genres.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Genres:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: manga.genres.map((genre) => Chip(
                        label: Text(genre),
                        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                      )).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
