import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'providers/catalog_provider.dart';
import 'providers/chapters_providers.dart';
import 'providers/favorites_provider.dart';
import 'providers/manga_provider.dart';
import 'providers/search_provider.dart';
import 'providers/read_chapters_provider.dart';
import 'providers/reading_history_provider.dart';

import 'screens/home_tab.dart';
import 'screens/search_screen.dart';
import 'services/mangakakalot_service.dart';
import 'widgets/manga_card.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final prefs = await SharedPreferences.getInstance();
  final mangakakalotService = MangaKakalotService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CatalogProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider(prefs: prefs)),
        ChangeNotifierProvider(create: (_) => ChaptersProvider()),
        ChangeNotifierProvider(create: (_) => MangaProvider(prefs: prefs)),
        ChangeNotifierProvider(
            create: (_) => SearchProvider(mangakakalotService)),
        ChangeNotifierProvider(
            create: (_) => ReadChaptersProvider(prefs: prefs)),
        ChangeNotifierProvider(
            create: (_) => ReadingHistoryProvider(prefs: prefs)),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Manga Parade',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.black.withValues(alpha: 0.3),
          elevation: 0,
        ),

        // IMPORTANT: Flutter expects CardThemeData (not CardTheme)
        cardTheme: CardThemeData(
          color: Colors.black.withValues(alpha: 0.5),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const GradientBackground(child: HomePage()),
    );
  }
}

class GradientBackground extends StatelessWidget {
  final Widget child;

  const GradientBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A1A2E),
            Color(0xFF16213E),
            Color(0xFF0F3460),
            Color(0xFF1B1B1B),
          ],
        ),
      ),
      child: child,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    // Load Firestore catalog after the frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<CatalogProvider>().refresh();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manga Parade'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text('Continue Reading'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text('All Manga'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text('Search'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text('Favorites'),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          HomeTab(),
          CatalogGrid(showOnlyFavorites: false),
          SearchScreen(),
          CatalogGrid(showOnlyFavorites: true),
        ],
      ),
    );
  }
}

/// Firestore-backed grid (Step 1: no pagination yet)
class CatalogGrid extends StatefulWidget {
  final bool showOnlyFavorites;

  const CatalogGrid({super.key, required this.showOnlyFavorites});

  @override
  State<CatalogGrid> createState() => _CatalogGridState();
}

class _CatalogGridState extends State<CatalogGrid> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_onScroll);

    // If user lands on this tab first, make sure we have data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final catalog = context.read<CatalogProvider>();
      if (catalog.mangas.isEmpty && !catalog.isLoading) {
        catalog.refresh();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Load next page when 80% down
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      final catalog = context.read<CatalogProvider>();
      if (!catalog.isLoading && catalog.hasMore) {
        catalog.fetchNextPage();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final favorites = context.watch<FavoritesProvider>();

    final all = catalog.mangas;

    final displayed = widget.showOnlyFavorites
        ? all.where((m) => favorites.isFavorite(m)).toList()
        : all;

    if (catalog.isLoading && all.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (catalog.error != null && all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Firestore error:\n${catalog.error}',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => context.read<CatalogProvider>().refresh(),
                child: const Text('Retry'),
              )
            ],
          ),
        ),
      );
    }

    final grid = RefreshIndicator(
      onRefresh: () => context.read<CatalogProvider>().refresh(),
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(8.0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.7,
          crossAxisSpacing: 8.0,
          mainAxisSpacing: 8.0,
        ),
        itemCount: displayed.length + 1, // +1 for footer loader / end text
        itemBuilder: (context, index) {
          if (index < displayed.length) {
            final manga = displayed[index];
            return MangaCard(manga: manga);
          }

          // Footer slot
          if (widget.showOnlyFavorites) {
            return const SizedBox.shrink();
          }

          if (catalog.isLoading) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          if (!catalog.hasMore) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'That’s the whole parade 🎉',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );

    if (widget.showOnlyFavorites) {
      return grid;
    }

    return Column(
      children: [
        _buildSourceFilterRow(context, catalog),
        Expanded(child: grid),
      ],
    );
  }

  Widget _buildSourceFilterRow(BuildContext context, CatalogProvider provider) {
    final sources = [
      {'id': 'all', 'label': 'All'},
      {'id': 'mangadex', 'label': 'MD'},
      {'id': 'comick', 'label': 'CK'},
      {'id': 'qiscans', 'label': 'QS'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        children: sources.map((src) {
          final isSelected = provider.selectedSource == src['id'];
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              selected: isSelected,
              label: Text(
                src['label']!,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 12,
                ),
              ),
              backgroundColor: Colors.white10,
              selectedColor: Theme.of(context).primaryColor,
              onSelected: (_) => provider.setSourceFilter(src['id']!),
            ),
          );
        }).toList(),
      ),
    );
  }
}
