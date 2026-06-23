import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/catalog_provider.dart';
import '../widgets/manga_card.dart';

enum ViewAllType { recentlyUpdated, mostPopular }

class ViewAllScreen extends StatefulWidget {
  final ViewAllType type;

  const ViewAllScreen({super.key, required this.type});

  @override
  State<ViewAllScreen> createState() => _ViewAllScreenState();
}

class _ViewAllScreenState extends State<ViewAllScreen> {
  final _controller = ScrollController();

  bool get _isRecentlyUpdated => widget.type == ViewAllType.recentlyUpdated;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final catalog = context.read<CatalogProvider>();
      if (_isRecentlyUpdated) {
        await catalog.resetRecentlyUpdatedAll();
      } else {
        await catalog.resetMostPopularAll();
      }
    });

    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;

    final max = _controller.position.maxScrollExtent;
    final current = _controller.position.pixels;

    if (current >= max * 0.8) {
      final catalog = context.read<CatalogProvider>();
      if (_isRecentlyUpdated) {
        if (!catalog.isLoadingRecentlyUpdatedAll &&
            catalog.hasMoreRecentlyUpdatedAll) {
          catalog.fetchNextRecentlyUpdatedAllPage();
        }
      } else {
        if (!catalog.isLoadingMostPopularAll && catalog.hasMoreMostPopularAll) {
          catalog.fetchNextMostPopularAllPage();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();

    final title = _isRecentlyUpdated ? 'Recently Updated' : 'Most Popular';

    final items = _isRecentlyUpdated
        ? catalog.recentlyUpdatedAll
        : catalog.mostPopularAll;
    final isLoading = _isRecentlyUpdated
        ? catalog.isLoadingRecentlyUpdatedAll
        : catalog.isLoadingMostPopularAll;
    final hasMore = _isRecentlyUpdated
        ? catalog.hasMoreRecentlyUpdatedAll
        : catalog.hasMoreMostPopularAll;
    final error = _isRecentlyUpdated
        ? catalog.recentlyUpdatedAllError
        : catalog.mostPopularAllError;

    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    final crossAxisCount = isTablet ? 4 : 2;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: RefreshIndicator(
        onRefresh: () async {
          final c = context.read<CatalogProvider>();
          if (_isRecentlyUpdated) {
            await c.resetRecentlyUpdatedAll();
          } else {
            await c.resetMostPopularAll();
          }
        },
        child: Builder(
          builder: (_) {
            if (error != null && items.isEmpty) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child:
                        Text(error, style: const TextStyle(color: Colors.red)),
                  ),
                ],
              );
            }

            if (items.isEmpty && isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            return GridView.builder(
              controller: _controller,
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 0.7,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: items.length + 1, // footer slot
              itemBuilder: (context, index) {
                if (index < items.length) {
                  return MangaCard(manga: items[index]);
                }

                if (isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!hasMore) {
                  return const Center(
                    child: Text(
                      'End of the scroll 📚',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                return const SizedBox.shrink();
              },
            );
          },
        ),
      ),
    );
  }
}
