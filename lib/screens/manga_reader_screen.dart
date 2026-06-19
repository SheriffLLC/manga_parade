import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/fs_chapter.dart';
import '../providers/chapters_providers.dart';
import '../screens/chapter_reader_screen.dart';
import '../widgets/manga_image.dart';

class MangaReaderScreen extends StatefulWidget {
  final Manga manga;

  const MangaReaderScreen({super.key, required this.manga});

  @override
  State<MangaReaderScreen> createState() => _MangaReaderScreenState();
}

class _MangaReaderScreenState extends State<MangaReaderScreen> {
  bool _ensured = false;
  String? _ensureError;

  @override
  void initState() {
    super.initState();

    final source = (widget.manga.source ?? '').toLowerCase();

    // Kick off in-app chapter loading only for sources the reader supports.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (source == 'qiscans') {
          if (mounted) setState(() => _ensured = true);
        } else if (source == 'mangadex') {
          await context
              .read<ChaptersProvider>()
              .ensureChaptersIndexed(widget.manga.id);
          if (mounted) setState(() => _ensured = true);
        } else if (mounted) {
          setState(() {
            _ensureError = 'In-app chapters are only available for MangaDex.';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _ensureError = e.toString();
          });
        }
      }
    });
  }

  Chapter _chapterFromFs(FsChapter chapter) {
    return Chapter(
      id: chapter.id,
      title: chapter.title,
      sourceUrl: chapter.sourceUrl,
      source: widget.manga.source ?? 'mangadex',
      chapterNumber: chapter.chapterNumber,
      index: chapter.index,
      publishedAt: chapter.publishedAt,
      chapter: chapter.chapterNumber,
      translatedLanguage: 'en',
      publishAt: chapter.publishedAt ?? DateTime.now(),
      pages: 0,
    );
  }

  Future<void> _openSourceUrl() async {
    final rawUrl = widget.manga.sourceUrl?.trim();
    final uri = rawUrl == null || rawUrl.isEmpty ? null : Uri.tryParse(rawUrl);

    if (uri == null || !uri.hasScheme) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No QiScans link is available.')),
      );
      return;
    }

    final didLaunch = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!didLaunch && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open QiScans.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final manga = widget.manga;
    final description = manga.description.trim();
    final heroTag = 'manga_cover_${manga.id}_${manga.coverUrl.hashCode}';
    final isQiscans = (manga.source ?? '').toLowerCase() == 'qiscans';
    final isMangadex = (manga.source ?? '').toLowerCase() == 'mangadex';

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
                  tag: heroTag,
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
                      imageUrl: manga.coverUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                title: Text(
                  manga.title,
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
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        description.isNotEmpty
                            ? description
                            : 'No description available.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withOpacity(0.9),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chapters',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    if (!isQiscans && _ensureError == null)
                      Text(
                        _ensured ? 'Chapter sync OK' : 'Ensuring chapters…',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    if (_ensureError != null) ...[
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Chapter sync failed: $_ensureError',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                    if (isQiscans)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _openSourceUrl,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open on QiScans'),
                        ),
                      )
                    else if (isMangadex)
                      StreamBuilder<List<FsChapter>>(
                        stream: context
                            .watch<ChaptersProvider>()
                            .watchChapters(widget.manga.id),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          if (snapshot.hasError) {
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'Error loading chapters: ${snapshot.error}',
                                style: const TextStyle(color: Colors.red),
                              ),
                            );
                          }

                          final fsChapters =
                              snapshot.data ?? const <FsChapter>[];
                          if (fsChapters.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: Text('No chapters found.')),
                            );
                          }

                          final chapters =
                              fsChapters.map(_chapterFromFs).toList();

                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: chapters.length,
                            itemBuilder: (context, i) {
                              final ch = chapters[i];
                              return ListTile(
                                title: Text(ch.title),
                                subtitle: ch.chapterNumber.isEmpty
                                    ? null
                                    : Text('Chapter ${ch.chapterNumber}'),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ChapterReaderScreen(
                                        manga: widget.manga,
                                        chapter: ch,
                                        allChapters: chapters,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'In-app chapters are available for MangaDex titles.',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
