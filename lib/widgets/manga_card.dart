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
  final String? heroPrefix;

  const MangaCard({
    super.key,
    required this.manga,
    this.onTap,
    this.subtitle,
    this.heroPrefix,
  });

  @override
  Widget build(BuildContext context) {
    final heroTag = '${heroPrefix ?? ''}manga_cover_${manga.id}_${manga.coverUrl.hashCode}';
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: onTap ??
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MangaReaderScreen(manga: manga),
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
                    tag: heroTag,
                    child: MangaImage(
                      imageUrl: manga.coverUrl,
                      fit: BoxFit.cover,
                      isCover: true,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _buildSourceBadge(manga.source),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Consumer<FavoritesProvider>(
                      builder: (context, favoritesProvider, child) {
                        final isFavorite = favoritesProvider.isFavorite(manga);
                        return CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.surface,
                          child: IconButton(
                            icon: Icon(
                              isFavorite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: isFavorite ? Colors.red : null,
                            ),
                            onPressed: () =>
                                favoritesProvider.toggleFavorite(manga),
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
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.7),
                      ),
                    ),
                  ],
                  if (manga.volumes != null || manga.chapters != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (manga.volumes != null) ...[
                          Icon(Icons.book,
                              size: 12,
                              color: Theme.of(context).colorScheme.primary),
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
                          Icon(Icons.menu_book,
                              size: 12,
                              color: Theme.of(context).colorScheme.primary),
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

  Widget _buildSourceBadge(String? source) {
    if (source == null || source.isEmpty) return const SizedBox.shrink();

    String label = 'MD';
    Color color = Colors.blue;
    if (source.toLowerCase() == 'comick') {
      label = 'CK';
      color = Colors.green;
    } else if (source.toLowerCase() == 'qiscans') {
      label = 'QS';
      color = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
