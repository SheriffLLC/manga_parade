import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/fs_chapter.dart';
import '../providers/chapters_providers.dart';
import '../providers/catalog_provider.dart';
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

    // Diagnostic logging
    debugPrint('[Diagnostic] source=$source mangaId=${widget.manga.id}');

    // Kick off in-app chapter loading only for sources the reader supports.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (source == 'qiscans') {
          if (mounted) setState(() => _ensured = true);
        } else if (source == 'mangadex' || source == 'comick') {
          await context
              .read<ChaptersProvider>()
              .ensureChaptersIndexed(widget.manga.id);
          if (mounted) setState(() => _ensured = true);
        } else if (mounted) {
          setState(() {
            _ensureError = 'In-app chapters are only available for MangaDex and ComicK.';
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
    return StreamBuilder<Manga>(
      stream: context.read<CatalogProvider>().watchManga(widget.manga.id),
      initialData: widget.manga,
      builder: (context, mangaSnapshot) {
        final manga = mangaSnapshot.data ?? widget.manga;
        final description = manga.description.trim();
        final heroTag = 'manga_cover_${manga.id}_${manga.coverUrl.hashCode}';
        final isQiscans = (manga.source ?? '').toLowerCase() == 'qiscans';
        final isMangadex = (manga.source ?? '').toLowerCase() == 'mangadex';
        final isComick = (manga.source ?? '').toLowerCase() == 'comick';

        final isSyncing = isComick && manga.chapterSyncStatus == 'syncing';
        final isSyncFailed = isComick && manga.chapterSyncStatus == 'failed';

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
                        if (!isQiscans && _ensureError == null && !isSyncFailed)
                          Text(
                            isSyncing
                                ? 'Syncing chapters…'
                                : (_ensured ? 'Chapter sync OK' : 'Ensuring chapters…'),
                            style: const TextStyle(color: Colors.white54),
                          ),
                        if (_ensureError != null || isSyncFailed) ...[
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _ensureError != null
                                      ? 'Chapter sync failed: $_ensureError'
                                      : 'Chapter sync failed: ${manga.chapterSyncError ?? "Unknown ComicK sync error"}',
                                  style: const TextStyle(color: Colors.red),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    setState(() {
                                      _ensureError = null;
                                      _ensured = false;
                                    });
                                    try {
                                      await context
                                          .read<ChaptersProvider>()
                                          .ensureChaptersIndexed(manga.id, force: true);
                                      setState(() {
                                        _ensured = true;
                                      });
                                    } catch (e) {
                                      setState(() {
                                        _ensureError = e.toString();
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry Chapter Sync'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red[800],
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
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
                        else if (isMangadex || isComick)
                          StreamBuilder<List<FsChapter>>(
                            stream: context
                                .watch<ChaptersProvider>()
                                .watchChapters(manga.id),
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
                                if (isSyncing || (isComick && manga.chapterSyncStatus == null)) {
                                  return const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircularProgressIndicator(),
                                          SizedBox(height: 16),
                                          Text(
                                            'Syncing chapters from ComicK via Apify...\nThis takes about a minute. They will appear here automatically.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(color: Colors.white70),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
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
                                    subtitle: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (ch.source.toLowerCase() == 'comick') ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                                            ),
                                            child: const Text(
                                              'CK • CBZ',
                                              style: TextStyle(
                                                color: Colors.greenAccent,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        if (ch.chapterNumber != null && ch.chapterNumber!.isNotEmpty)
                                          Text('Chapter ${ch.chapterNumber}'),
                                      ],
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ChapterReaderScreen(
                                            manga: manga,
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
                                'In-app chapters are available for MangaDex and ComicK titles.',
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
      },
    );
  }
}
