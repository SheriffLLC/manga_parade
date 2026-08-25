import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/search_provider.dart';
import '../providers/catalog_provider.dart';
import '../widgets/manga_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Clear previous search results when screen is opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SearchProvider>().search('');
      }
    });
    
    // Add scroll listener for infinite scrolling
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8) {
      final provider = Provider.of<SearchProvider>(context, listen: false);
      if (provider.selectedGenre != null && !provider.isLoadingMore && provider.hasMoreResults) {
        provider.loadMoreGenreResults();
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce != null) {
      _debounce!.cancel();
    }
    _debounce = Timer(Duration(milliseconds: 500), () {
      if (mounted) {
        context.read<SearchProvider>().search(query);
      }
      _debounce = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search bar
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search manga',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    final query = _searchController.text.trim();
                    if (query.isNotEmpty) {
                      Provider.of<SearchProvider>(context, listen: false)
                          .search(query);
                    }
                  },
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (query) {
                if (query.trim().isNotEmpty) {
                  Provider.of<SearchProvider>(context, listen: false)
                      .search(query.trim());
                }
              },
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 12),
            
            Consumer<SearchProvider>(
              builder: (context, provider, child) {
                final sources = [
                  {'id': 'all', 'label': 'All'},
                  {'id': 'mangadex', 'label': 'MD'},
                  {'id': 'comick', 'label': 'CK'},
                  {'id': 'qiscans', 'label': 'QS'},
                ];

                return Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
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
                                onSelected: (_) {
                                  provider.setSourceFilter(src['id']!);
                                  final query = _searchController.text.trim();
                                  if (query.isNotEmpty) {
                                    provider.search(query);
                                  }
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    if (provider.selectedSource == 'comick')
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent),
                        tooltip: 'Import ComicK URL',
                        onPressed: () => _showImportComickDialog(context),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            
            // Genre filter section with a title
            const Text(
              'Filter by Genre',
              style: TextStyle(
                fontSize: 18, 
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            // Genre filter chips
            Consumer<SearchProvider>(
              builder: (context, provider, child) {
                return Container(
                  height: 50,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: SearchProvider.availableGenres.length,
                    itemBuilder: (context, index) {
                      final genre = SearchProvider.availableGenres[index];
                      final isSelected = provider.selectedGenre == genre;
                      
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text(genre),
                          selected: isSelected,
                          onSelected: (selected) {
                            // Clear the search field when selecting a genre
                            _searchController.clear();
                            provider.setSelectedGenre(selected ? genre : null);
                          },
                          backgroundColor: Colors.grey[200],
                          selectedColor: Colors.blue[100],
                          checkmarkColor: Colors.blue[800],
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.blue[800] : Colors.black,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            
            // Display selected genre as a header if one is selected
            Consumer<SearchProvider>(
              builder: (context, provider, child) {
                return provider.selectedGenre != null
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'Showing manga in genre: ${provider.selectedGenre}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      )
                    : const SizedBox.shrink();
              },
            ),
            
            const SizedBox(height: 16),
            
            // Search results
            Expanded(
              child: Consumer<SearchProvider>(
                builder: (context, provider, child) {
                  if (provider.isSearching && provider.searchResults.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  
                  if (provider.error != null && provider.searchResults.isEmpty) {
                    return Center(child: Text('Error: ${provider.error}'));
                  }
                  
                  if (provider.searchResults.isEmpty) {
                    if (provider.selectedSource == 'comick') {
                      final query = _searchController.text.trim();
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.search_off, size: 48, color: Colors.white60),
                              const SizedBox(height: 16),
                              Text(
                                query.isEmpty
                                    ? 'No indexed ComicK titles yet.'
                                    : 'No indexed ComicK titles match "$query"',
                                style: const TextStyle(color: Colors.white70, fontSize: 15),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () => _showImportComickDialog(context),
                                icon: const Icon(Icons.add),
                                label: const Text('Import ComicK URL'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[800],
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return const Center(
                      child: Text(
                        'No results found. Try a different search or genre.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  
                  return Stack(
                    children: [
                      GridView.builder(
                        controller: _scrollController,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.7,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: provider.searchResults.length,
                        itemBuilder: (context, index) {
                          final manga = provider.searchResults[index];
                          return MangaCard(manga: manga);
                        },
                      ),
                      if (provider.isLoadingMore)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 80,
                            alignment: Alignment.center,
                            child: const CircularProgressIndicator(),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImportComickDialog(BuildContext context) {
    final textController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Import ComicK Title'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter ComicK manga URL:',
                    style: TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    autofocus: true,
                    enabled: !isSubmitting,
                    decoration: const InputDecoration(
                      hintText: 'https://comick.io/comic/00-sousou-no-frieren',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final url = textController.text.trim();
                          if (url.isEmpty || !url.contains('comick.io/comic/')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter a valid ComicK URL')),
                            );
                            return;
                          }

                          setState(() {
                            isSubmitting = true;
                          });

                          try {
                            // Call importComicK on CatalogProvider (since CatalogProvider holds import methods)
                            await Provider.of<CatalogProvider>(context, listen: false).importComicK(url);
                            if (context.mounted) {
                              Navigator.pop(dialogContext);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Successfully queued ComicK import!')),
                              );
                              // Clear and re-search to locate new manga if query exists
                              final query = _searchController.text.trim();
                              if (query.isNotEmpty) {
                                Provider.of<SearchProvider>(context, listen: false).search(query);
                              }
                            }
                          } catch (e) {
                            if (context.mounted) {
                              setState(() {
                                isSubmitting = false;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Import failed: ${e.toString().replaceAll('Exception: ', '')}')),
                              );
                            }
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Import'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
