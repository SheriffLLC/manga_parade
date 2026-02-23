import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/manga.dart';
import '../models/fs_chapter.dart';
import '../providers/chapters_providers.dart';
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
  bool _isLoadingQiscans = false;
  List<FsChapter> _qiscansChapters = const <FsChapter>[];

  @override
  void initState() {
    super.initState();

    final source = (widget.manga.source ?? '').toLowerCase();

    // kick off chapter loading once
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (source == 'qiscans') {
          final postId = widget.manga.qiscansPostId;
          if (postId == null || postId <= 0) {
            if (mounted) {
              setState(() {
                _ensureError = 'Missing qiscansPostId for this manga.';
              });
            }
            return;
          }

          if (mounted) {
            setState(() {
              _isLoadingQiscans = true;
              _ensureError = null;
            });
          }

          final chapters = await context
              .read<ChaptersProvider>()
              .fetchQiscansChapters(postId, page: 1, perPage: 200);

          if (mounted) {
            setState(() {
              _qiscansChapters = chapters;
              _isLoadingQiscans = false;
              _ensured = true;
            });
          }
        } else {
          await context
              .read<ChaptersProvider>()
              .ensureChaptersIndexed(widget.manga.id);
          if (mounted) setState(() => _ensured = true);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _ensureError = e.toString();
            _isLoadingQiscans = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final manga = widget.manga;
    final description = manga.description.trim();
    final heroTag = 'manga_cover_${manga.id}_${manga.coverUrl.hashCode}';
    final isQiscans = (manga.source ?? '').toLowerCase() == 'qiscans';

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
                    Text(
                      'DEBUG manga.id = ${widget.manga.id}',
                      style: const TextStyle(color: Colors.white54),
                    ),
                    if (_ensureError == null)
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
                    if (isQiscans && _isLoadingQiscans)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (isQiscans && _qiscansChapters.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('No chapters found.')),
                      )
                    else if (isQiscans)
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _qiscansChapters.length,
                        itemBuilder: (context, i) {
                          final ch = _qiscansChapters[i];
                          return ListTile(
                            title: Text(ch.title),
                            subtitle: ch.chapterNumber.isEmpty
                                ? null
                                : Text('Chapter ${ch.chapterNumber}'),
                            onTap: () {
                              // Later: open chapter reader using ch.sourceUrl
                              // Navigator.push(...);
                            },
                          );
                        },
                      )
                    else
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

                          final chapters = snapshot.data ?? const <FsChapter>[];
                          if (chapters.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: Text('No chapters found.')),
                            );
                          }

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
                                  // Later: open chapter reader using ch.sourceUrl
                                  // Navigator.push(...);
                                },
                              );
                            },
                          );
                        },
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
