import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/manga.dart';
import '../providers/manga_provider.dart';
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
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<MangaProvider>().fetchMangas(refresh: true);
      }
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
        body: Consumer<MangaProvider>(
          builder: (context, provider, child) {
            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  floating: true,
                  snap: true,
                  backgroundColor: Colors.transparent,
                  title: const Text('Manga Parade'),
                  actions: [
                    IconButton(
                      icon: Icon(
                        _showOnlyFavorites ? Icons.favorite : Icons.favorite_border,
                        color: _showOnlyFavorites ? Colors.red : null,
                      ),
                      onPressed: () {
                        setState(() {
                          _showOnlyFavorites = !_showOnlyFavorites;
                        });
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
                              builder: (context) => MangaReaderScreen(
                                manga: selectedManga,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ],
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
                              onPressed: () => provider.fetchMangas(refresh: true),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  const SliverToBoxAdapter(
                    child: ContinueReadingSection(),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Text(
                        'Popular Manga',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: MangaGrid(showOnlyFavorites: _showOnlyFavorites),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
