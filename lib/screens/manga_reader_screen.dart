import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
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

  Future<void> _launchExternalUrl(BuildContext context, String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open page: $urlString')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();

    final source = (widget.manga.source ?? '').toLowerCase();

    // kick off chapter loading once
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (source == 'qiscans' || source == 'asurascans') {
          // Skip in-app chapter syncing/scraping due to block
          if (mounted) {
            setState(() {
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
    final isRedirectOnly = (manga.source ?? '').toLowerCase() == 'qiscans' ||
        (manga.source ?? '').toLowerCase() == 'asurascans';

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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Chapters',
                          style:
                              TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        if (!isRedirectOnly)
                          Expanded(
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (manga.qiscansSourceUrl != null && manga.qiscansSourceUrl!.isNotEmpty)
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () => _launchExternalUrl(context, manga.qiscansSourceUrl!),
                                    icon: const Icon(Icons.open_in_new, size: 14, color: Colors.blueAccent),
                                    label: const Text(
                                      'Open on QiScans',
                                      style: TextStyle(color: Colors.blueAccent, fontSize: 12),
                                    ),
                                  ),
                                if (manga.asurascansSourceUrl != null && manga.asurascansSourceUrl!.isNotEmpty)
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () => _launchExternalUrl(context, manga.asurascansSourceUrl!),
                                    icon: const Icon(Icons.open_in_new, size: 14, color: Colors.blueAccent),
                                    label: const Text(
                                      'Open on Asura Scans',
                                      style: TextStyle(color: Colors.blueAccent, fontSize: 12),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'DEBUG manga.id = ${widget.manga.id}',
                      style: const TextStyle(color: Colors.white54),
                    ),
                    if (!isRedirectOnly) ...[
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
                    ],
                    if (isRedirectOnly)
                      _buildRedirectCard(context, manga)
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
                                subtitle: ((ch.chapterNumber as String?)?.isEmpty ?? true)
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

  Widget _buildRedirectCard(BuildContext context, Manga manga) {
    final source = (manga.source ?? '').toLowerCase();
    final sourceName = source == 'asurascans' ? 'Asura Scans' : 'QiScans';
    final url = (manga.sourceUrl != null && manga.sourceUrl!.isNotEmpty)
        ? manga.sourceUrl!
        : (source == 'asurascans' ? manga.asurascansSourceUrl : manga.qiscansSourceUrl) ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blueAccent[100], size: 28),
              const SizedBox(width: 12),
              Text(
                'Read on $sourceName',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'In-app reading is temporarily unavailable for this title. You can read all chapters directly on $sourceName.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          if (url.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _launchExternalUrl(context, url),
                    icon: const Icon(Icons.open_in_browser, size: 20),
                    label: Text(
                      'Open on $sourceName',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white30),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _launchExternalUrl(context, url),
                    icon: const Icon(Icons.chrome_reader_mode, size: 20),
                    label: const Text(
                      'Read Latest',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            const Text(
              'No source URL available for this title.',
              style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }
}
