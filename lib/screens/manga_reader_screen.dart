import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chapter.dart';
import '../models/manga.dart';
import '../providers/favorites_provider.dart';
import '../providers/manga_provider.dart';
import '../providers/read_chapters_provider.dart';
import '../services/mangakakalot_service.dart';
import '../widgets/manga_image.dart';
import './chapter_reader_screen.dart';

class MangaReaderScreen extends StatefulWidget {
  final Manga manga;

  const MangaReaderScreen({super.key, required this.manga});

  @override
  State<MangaReaderScreen> createState() => _MangaReaderScreenState();
}

class _MangaReaderScreenState extends State<MangaReaderScreen> {
  Chapter? _selectedChapter;
  List<Chapter> _chapters = [];
  bool _isLoadingChapters = false;
  String? _error;
  final _mangakakalotService = MangaKakalotService();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadChapters();
      }
    });
  }

  @override
  void dispose() {
    _mangakakalotService.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadChapters() async {
    if (!mounted) return;

    try {
      setState(() {
        _isLoadingChapters = true;
        _error = null;
      });

      List<Chapter> chapters;
      if (widget.manga.id.contains('mangadex')) {
        final mangaProvider = context.read<MangaProvider>();
        chapters = await mangaProvider.fetchChapters(widget.manga.id);
      } else {
        chapters = await _mangakakalotService.fetchChapters(widget.manga.id);
      }

      if (!mounted) return;

      setState(() {
        _chapters = chapters;
        _selectedChapter = chapters.isNotEmpty ? chapters[0] : null;
        _isLoadingChapters = false;
      });
    } catch (e, stackTrace) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _isLoadingChapters = false;
      });
    }
  }

  Widget _buildChapterList() {
    if (_chapters.isEmpty) {
      return const Center(child: Text('No chapters available'));
    }

    // Group chapters by volume
    final Map<String?, List<Chapter>> volumeChapters = {};
    for (final chapter in _chapters) {
      final volume = chapter.volume;
      if (!volumeChapters.containsKey(volume)) {
        volumeChapters[volume] = [];
      }
      volumeChapters[volume]!.add(chapter);
    }

    // Sort volumes
    final sortedVolumes = volumeChapters.keys.toList()
      ..sort((a, b) {
        if (a == null) return 1;
        if (b == null) return -1;
        return double.parse(b).compareTo(double.parse(a)); // Newest first
      });

    return ListView.builder(
      controller: _scrollController,
      itemCount: sortedVolumes.length,
      itemBuilder: (context, volumeIndex) {
        final volume = sortedVolumes[volumeIndex];
        final chapters = volumeChapters[volume]!;

        // Sort chapters within volume
        chapters.sort((a, b) {
          final aNum = double.tryParse(a.chapter ?? '0') ?? 0;
          final bNum = double.tryParse(b.chapter ?? '0') ?? 0;
          return bNum.compareTo(aNum); // Newest first
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (volume != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Volume $volume',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ...chapters.map((chapter) {
              final readChaptersProvider = context.watch<ReadChaptersProvider>();
              final isRead = readChaptersProvider.isChapterRead(chapter.id);
              
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  title: Text(
                    chapter.title,
                    style: TextStyle(
                      color: isRead ? Colors.grey : Colors.white,
                    ),
                  ),
                  subtitle: chapter.scanlationGroup != null
                      ? Text(
                          'Scanlation: ${chapter.scanlationGroup}',
                          style: TextStyle(
                            color: isRead ? Colors.grey.withOpacity(0.7) : Colors.white70,
                          ),
                        )
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${chapter.pages} pages',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isRead ? Colors.grey : Colors.white70,
                            ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          isRead ? Icons.check_circle : Icons.check_circle_outline,
                          color: isRead ? Colors.green : Colors.grey,
                        ),
                        onPressed: () {
                          if (isRead) {
                            readChaptersProvider.markChapterAsUnread(chapter.id);
                          } else {
                            readChaptersProvider.markChapterAsRead(chapter.id);
                          }
                        },
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChapterReaderScreen(
                          manga: widget.manga,
                          chapter: chapter,
                          allChapters: chapters, // Pass the current volume's chapters
                        ),
                      ),
                    ).then((_) {
                      // Mark chapter as read when returning from reader
                      if (!readChaptersProvider.isChapterRead(chapter.id)) {
                        readChaptersProvider.markChapterAsRead(chapter.id);
                      }
                    });
                  },
                ),
              );
            }),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
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
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 200.0,
              pinned: true,
              backgroundColor: Colors.black.withOpacity(0.3),
              flexibleSpace: FlexibleSpaceBar(
                background: Hero(
                  tag: 'manga_cover_${widget.manga.id}',
                  child: ShaderMask(
                    shaderCallback: (Rect bounds) {
                      return LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.8),
                        ],
                      ).createShader(bounds);
                    },
                    blendMode: BlendMode.darken,
                    child: MangaImage(
                      imageUrl: widget.manga.coverUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                title: Text(
                  widget.manga.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.manga.description.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.manga.description,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withOpacity(0.9),
                              ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Chapters',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          if (_isLoadingChapters)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Error: $_error',
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadChapters,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F3460),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverFillRemaining(
                child: _buildChapterList(),
              ),
          ],
        ),
      ),
    );
  }
}
