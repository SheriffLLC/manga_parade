import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/manga.dart';
import '../providers/catalog_provider.dart';
import '../providers/favorites_provider.dart';
import '../widgets/manga_grid.dart';
import '../widgets/continue_reading_section.dart';
import '../screens/manga_reader_screen.dart';
import '../widgets/manga_card.dart';

class MangaSearchDelegate extends SearchDelegate<Manga?> {
  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: TextStyle(color: Colors.white60),
      ),
      textTheme: theme.textTheme.copyWith(
        titleLarge: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
      ),
    );
  }

  @override
  TextStyle? get searchFieldStyle => const TextStyle(color: Colors.white);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () => query = '',
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Text(
          query.isEmpty
              ? 'Enter a manga title to search'
              : 'Search results coming soon!',
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Text(
          query.isEmpty
              ? 'Enter a manga title to search'
              : 'Search suggestions coming soon!',
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _showOnlyFavorites = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final catalog = context.read<CatalogProvider>();
      await catalog.refreshHome();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue[900]!,
            Colors.purple[900]!,
          ],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Consumer<CatalogProvider>(
          builder: (context, provider, child) {
            return RefreshIndicator(
              onRefresh: provider.refreshHome,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    floating: true,
                    snap: true,
                    backgroundColor: Colors.transparent,
                    title: const Text('Manga Parade'),
                    actions: [
                      IconButton(
                        icon: Icon(
                          _showOnlyFavorites
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: _showOnlyFavorites ? Colors.red : null,
                        ),
                        onPressed: () {
                          setState(
                              () => _showOnlyFavorites = !_showOnlyFavorites);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () async {
                          final selectedManga = await showSearch<Manga?>(
                            context: context,
                            delegate: MangaSearchDelegate(),
                          );
                          if (selectedManga != null && mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    MangaReaderScreen(manga: selectedManga),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),

                  // Continue Reading
                  const SliverToBoxAdapter(child: ContinueReadingSection()),

                  // Recently Updated (horizontal rail)
                  SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: 'Recently Updated',
                      trailing: provider.isLoadingRecentlyUpdated
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 250,
                      child: Builder(
                        builder: (context) {
                          if (provider.recentlyUpdatedError != null &&
                              provider.recentlyUpdated.isEmpty) {
                            return _InlineError(
                              message: provider.recentlyUpdatedError!,
                              onRetry: () => provider.loadRecentlyUpdated(),
                            );
                          }

                          if (provider.isLoadingRecentlyUpdated &&
                              provider.recentlyUpdated.isEmpty) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          if (provider.recentlyUpdated.isEmpty) {
                            return const Center(
                              child: Text(
                                'Nothing yet (waiting on updates)',
                                style: TextStyle(color: Colors.white70),
                              ),
                            );
                          }

                          return ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            scrollDirection: Axis.horizontal,
                            itemCount: provider.recentlyUpdated.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final manga = provider.recentlyUpdated[index];
                              final isFav = context
                                  .read<FavoritesProvider>()
                                  .isFavorite(manga);

                              // If user toggled favorites-only, filter the rail too
                              if (_showOnlyFavorites && !isFav) {
                                return const SizedBox.shrink();
                              }

                              return SizedBox(
                                width: 150,
                                child: MangaCard(
                                  manga: manga,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            MangaReaderScreen(manga: manga),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),

                  // All Manga (grid)
                  const SliverToBoxAdapter(
                    child: _SectionHeader(title: 'All Manga'),
                  ),

                  if (provider.isLoading && provider.mangas.isEmpty)
                    const SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    )
                  else if (provider.error != null && provider.mangas.isEmpty)
                    SliverToBoxAdapter(
                      child: _InlineError(
                        message: provider.error!,
                        onRetry: () => provider.loadPopular(),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: MangaGrid(showOnlyFavorites: _showOnlyFavorites),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Row(
        children: [
          Expanded(child: Text(title, style: style)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InlineError({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              message,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
