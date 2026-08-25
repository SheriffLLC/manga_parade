import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/manga.dart';
import '../models/chapter.dart';
import '../models/manga_page.dart';
import '../providers/manga_provider.dart';
import '../providers/read_chapters_provider.dart';
import '../providers/reading_history_provider.dart';
import '../widgets/manga_image.dart';

class ChapterReaderScreen extends StatefulWidget {
  final Chapter chapter;
  final Manga manga;
  final List<Chapter>? allChapters; 

  const ChapterReaderScreen({
    super.key,
    required this.chapter,
    required this.manga,
    this.allChapters,
  });

  @override
  State<ChapterReaderScreen> createState() => _ChapterReaderScreenState();
}

class _ChapterReaderScreenState extends State<ChapterReaderScreen> {
  final PageController _pageController = PageController();
  final ScrollController _verticalController = ScrollController();
  MangaPage? _mangaPage;
  bool _isLoading = true;
  String? _error;
  int _currentPage = 0;
  bool _showControls = true;
  bool _isVerticalMode = true;
  late ReadChaptersProvider _readChaptersProvider;
  late ReadingHistoryProvider _readingHistoryProvider;
  final List<double> _imageHeights = [];
  
  Chapter? _nextChapter;
  Chapter? _previousChapter;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _readChaptersProvider = context.read<ReadChaptersProvider>();
    _readingHistoryProvider = context.read<ReadingHistoryProvider>();
  }

  @override
  void initState() {
    super.initState();
    _verticalController.addListener(_updateCurrentPageFromScroll);
    
    _setupChapterNavigation();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadPages();
        _readingHistoryProvider.addToHistory(widget.manga, widget.chapter);
      }
    });
  }

  void _setupChapterNavigation() {
    if (widget.allChapters == null || widget.allChapters!.isEmpty) {
      return;
    }
    
    final currentIndex = widget.allChapters!.indexWhere(
      (c) => c.id == widget.chapter.id
    );
    
    if (currentIndex == -1) {
      return;
    }
    
    // Since chapters are sorted with newest first (index 0 is newest),
    // "Next Chapter" should point to the older chapter (higher index)
    if (currentIndex < widget.allChapters!.length - 1) {
      _nextChapter = widget.allChapters![currentIndex + 1];
    }
    
    // "Previous Chapter" should point to the newer chapter (lower index)
    if (currentIndex > 0) {
      _previousChapter = widget.allChapters![currentIndex - 1];
    }
  }

  @override
  void dispose() {
    // Use a post-frame callback to mark chapter as read after the widget tree is unlocked
    if (!_readChaptersProvider.isChapterRead(widget.chapter.id)) {
      // Schedule the operation for after the current frame is complete
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _readChaptersProvider.markChapterAsRead(widget.chapter.id);
      });
    }
    _pageController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  void _updateCurrentPageFromScroll() {
    if (!_isVerticalMode || _mangaPage == null || _imageHeights.isEmpty) return;
    
    final scrollPosition = _verticalController.position.pixels;
    double heightSum = 0;
    
    for (int i = 0; i < _imageHeights.length; i++) {
      final imageHeight = _imageHeights[i];
      if (scrollPosition < heightSum + (imageHeight / 2)) {
        if (_currentPage != i) {
          setState(() {
            _currentPage = i;
          });
        }
        break;
      }
      heightSum += imageHeight;
    }
  }

  void _recordImageHeight(int index, double height) {
    if (_imageHeights.length <= index) {
      while (_imageHeights.length < index) {
        _imageHeights.add(0);
      }
      _imageHeights.add(height);
    } else {
      _imageHeights[index] = height;
    }
  }

  Future<void> _loadPages() async {
    if (!mounted) return;

    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final mangaProvider = context.read<MangaProvider>();
      
      // Diagnostic logging on opening chapter reader
      final format = widget.chapter.source == 'comick' ? 'cbz' : 'network';
      debugPrint('[Diagnostic] opening chapter_reader_screen source=${widget.chapter.source} format=$format');

      final mangaPage = await mangaProvider.fetchChapterPages(widget.manga.id, widget.chapter);

      if (!mounted) return;

      setState(() {
        _mangaPage = mangaPage;
        _isLoading = false;
        _imageHeights.clear();
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _toggleScrollMode() {
    setState(() {
      _isVerticalMode = !_isVerticalMode;
    });
  }
  
  void _navigateToChapter(Chapter chapter) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ChapterReaderScreen(
          chapter: chapter,
          manga: widget.manga,
          allChapters: widget.allChapters,
        ),
      ),
    );
  }

  void _goToNextChapter() {
    if (_nextChapter != null) {
      _navigateToChapter(_nextChapter!);
    }
  }

  void _goToPreviousChapter() {
    if (_previousChapter != null) {
      _navigateToChapter(_previousChapter!);
    }
  }

  Widget _buildPageView() {
    if (_mangaPage == null) return const SizedBox.shrink();

    if (_isVerticalMode) {
      return SingleChildScrollView(
        controller: _verticalController,
        child: Column(
          children: List.generate(
            _mangaPage!.pageCount,
            (index) => GestureDetector(
              onTap: _toggleControls,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Container(
                    width: double.infinity,
                    constraints: BoxConstraints(
                      minHeight: MediaQuery.of(context).size.height * 0.5,
                    ),
                    child: MangaImageWithSizeNotifier(
                      imageUrl: _mangaPage!.getPageUrl(index),
                      fit: BoxFit.contain,
                      onSizeChanged: (size) {
                        _recordImageHeight(index, size.height);
                      },
                    ),
                  );
                }
              ),
            ),
          ),
        ),
      );
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: _mangaPage!.pageCount,
      onPageChanged: (index) {
        setState(() {
          _currentPage = index;
        });
      },
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: _toggleControls,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 3.0,
              child: MangaImage(
                imageUrl: _mangaPage!.getPageUrl(index),
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _showControls
          ? AppBar(
              backgroundColor: Colors.black.withValues(alpha: 0.7),
              title: Text(widget.chapter.title),
              actions: [
                IconButton(
                  icon: Icon(_isVerticalMode
                      ? Icons.view_carousel
                      : Icons.view_column),
                  onPressed: _toggleScrollMode,
                  tooltip: _isVerticalMode
                      ? 'Switch to horizontal mode'
                      : 'Switch to vertical mode',
                ),
              ],
            )
          : null,
      body: Stack(
        children: [
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Error loading pages:\n$_error',
                      style: const TextStyle(color: Colors.red, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _loadPages,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            _buildPageView(),
            
          if (_showControls)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Previous chapter button slot (newer chapter)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16.0),
                        child: _previousChapter != null
                            ? ElevatedButton.icon(
                                onPressed: _goToPreviousChapter,
                                icon: const Icon(Icons.arrow_back),
                                label: const Text('Newer'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(alpha: 0.7),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  
                  // Page indicator
                  if (_mangaPage != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Page ${_currentPage + 1}/${_mangaPage?.pageCount ?? 0}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  
                  // Next chapter button slot (older chapter)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16.0),
                        child: _nextChapter != null
                            ? ElevatedButton.icon(
                                onPressed: _goToNextChapter,
                                icon: const Icon(Icons.arrow_forward),
                                label: const Text('Older'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(alpha: 0.7),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class MangaImageWithSizeNotifier extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final void Function(Size) onSizeChanged;

  const MangaImageWithSizeNotifier({
    super.key,
    required this.imageUrl,
    required this.fit,
    required this.onSizeChanged,
  });

  @override
  State<MangaImageWithSizeNotifier> createState() => _MangaImageWithSizeNotifierState();
}

class _MangaImageWithSizeNotifierState extends State<MangaImageWithSizeNotifier> {
  int _retryKey = 0;

  void _reload() {
    setState(() {
      _retryKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isLocal = widget.imageUrl.startsWith('file://') ||
        (!widget.imageUrl.startsWith('http://') && !widget.imageUrl.startsWith('https://'));

    if (isLocal) {
      final cleanPath = widget.imageUrl.startsWith('file://') ? widget.imageUrl.substring(7) : widget.imageUrl;
      return Image.file(
        File(cleanPath),
        key: ValueKey(_retryKey),
        fit: widget.fit,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (frame != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final RenderBox renderBox = context.findRenderObject() as RenderBox;
              final size = renderBox.size;
              widget.onSizeChanged(size);
            });
          }
          return child;
        },
        errorBuilder: (context, error, stackTrace) {
          const size = Size(300, 450);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onSizeChanged(size);
          });
          return _buildErrorWidget();
        },
      );
    }

    return Image.network(
      widget.imageUrl,
      key: ValueKey(_retryKey),
      fit: widget.fit,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final RenderBox renderBox = context.findRenderObject() as RenderBox;
            final size = renderBox.size;
            widget.onSizeChanged(size);
          });
        }
        return child;
      },
      errorBuilder: (context, error, stackTrace) {
        const size = Size(300, 450);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onSizeChanged(size);
        });
        return _buildErrorWidget();
      },
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Container(
        width: double.infinity,
        height: 350,
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[950],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.signal_wifi_connected_no_internet_4,
              size: 32,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 8),
            const Text(
              'Page failed to load',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Reload', style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white10,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
