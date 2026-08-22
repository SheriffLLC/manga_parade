import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/manga.dart';
import '../providers/favorites_provider.dart';
import '../screens/manga_reader_screen.dart';
import 'manga_image.dart';

class RailMangaCard extends StatelessWidget {
  final Manga manga;

  /// Optional: show a small subtitle (like "Updated today", "Ch. 120", etc.)
  final String? subtitle;

  /// Optional: prefix to make Hero animations unique in subtrees
  final String? heroPrefix;

  /// Optional override
  final VoidCallback? onTap;

  const RailMangaCard({
    super.key,
    required this.manga,
    this.subtitle,
    this.heroPrefix,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final heroTag = '${heroPrefix ?? ''}manga_cover_${manga.id}_${manga.coverUrl.hashCode}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap ??
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MangaReaderScreen(manga: manga),
                ),
              );
            },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Poster
              Hero(
                tag: heroTag,
                child: MangaImage(
                  imageUrl: manga.coverUrl,
                  fit: BoxFit.cover,
                ),
              ),

              // Bottom gradient for readable text
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.85),
                      ],
                    ),
                  ),
                ),
              ),

              // Title + optional subtitle
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      manga.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Favorite button (top-right)
              Positioned(
                top: 8,
                right: 8,
                child: Consumer<FavoritesProvider>(
                  builder: (_, favorites, __) {
                    final isFav = favorites.isFavorite(manga);
                    return InkResponse(
                      radius: 22,
                      onTap: () => favorites.toggleFavorite(manga),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
                          ),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          isFav ? Icons.favorite : Icons.favorite_border,
                          size: 18,
                          color: isFav ? Colors.red : Colors.white,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
