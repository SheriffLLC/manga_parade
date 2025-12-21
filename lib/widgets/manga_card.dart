import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/manga.dart';
import '../providers/favorites_provider.dart';
import '../screens/manga_reader_screen.dart';
import 'manga_image.dart';

class MangaCard extends StatelessWidget {
  final Manga manga;
  final VoidCallback? onTap;
  final String? subtitle;

  const MangaCard({
    super.key, 
    required this.manga,
    this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: onTap ?? () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MangaReaderScreen(manga: manga),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'manga_cover_${manga.id}',
                    child: MangaImage(
                      imageUrl: manga.coverUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Consumer<FavoritesProvider>(
                      builder: (context, favoritesProvider, child) {
                        final isFavorite = favoritesProvider.isFavorite(manga);
                        return CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.surface,
                          child: IconButton(
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
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    manga.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                  if (manga.volumes != null || manga.chapters != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (manga.volumes != null) ...[
                          Icon(Icons.book, size: 12, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 2),
                          Text(
                            manga.volumes!,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (manga.chapters != null) ...[
                          Icon(Icons.menu_book, size: 12, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 2),
                          Text(
                            manga.chapters!,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
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
