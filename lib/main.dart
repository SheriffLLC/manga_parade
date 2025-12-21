import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'providers/manga_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/search_provider.dart';
import 'providers/read_chapters_provider.dart';
import 'providers/reading_history_provider.dart';
import 'services/mangakakalot_service.dart';
import 'widgets/manga_card.dart';
import 'widgets/continue_reading_grid.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final mangakakalotService = MangaKakalotService();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MangaProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider(prefs: prefs)),
        ChangeNotifierProvider(create: (_) => SearchProvider(mangakakalotService)),
        ChangeNotifierProvider(create: (_) => ReadChaptersProvider(prefs: prefs)),
        ChangeNotifierProvider(create: (_) => ReadingHistoryProvider(prefs: prefs)),
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
          backgroundColor: Colors.black.withOpacity(0.3),
          elevation: 0,
        ),
        cardTheme: CardTheme(
          color: Colors.black.withOpacity(0.5),
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
            Color(0xFF1A1A2E), // Deep navy blue
            Color(0xFF16213E), // Rich dark blue
            Color(0xFF0F3460), // Deep purple-blue
            Color(0xFF1B1B1B), // Almost black
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

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // Load manga list after the frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<MangaProvider>().fetchMangas();
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
          ContinueReadingGrid(),
          MangaGrid(showOnlyFavorites: false),
          SearchScreen(),
          MangaGrid(showOnlyFavorites: true),
        ],
      ),
    );
  }
}

class MangaGrid extends StatefulWidget {
  final bool showOnlyFavorites;

  const MangaGrid({super.key, required this.showOnlyFavorites});

  @override
  State<MangaGrid> createState() => _MangaGridState();
}

class _MangaGridState extends State<MangaGrid> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8) {
      final mangaProvider = context.read<MangaProvider>();
      if (!mangaProvider.isLoading && mangaProvider.hasMorePages) {
        mangaProvider.fetchMangas();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mangaProvider = context.watch<MangaProvider>();
    final favoritesProvider = context.watch<FavoritesProvider>();
    final mangas = mangaProvider.mangas;

    if (mangas.isEmpty && mangaProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final displayedMangas = widget.showOnlyFavorites
        ? favoritesProvider.favorites
        : mangas;

    return Stack(
      children: [
        GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(8.0),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.7,
            crossAxisSpacing: 8.0,
            mainAxisSpacing: 8.0,
          ),
          itemCount: displayedMangas.length,
          itemBuilder: (context, index) {
            final manga = displayedMangas[index];
            return MangaCard(manga: manga);
          },
        ),
        if (mangaProvider.isLoading)
          const Positioned(
            bottom: 16.0,
            left: 0,
            right: 0,
            child: Center(
              child: CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }
}
