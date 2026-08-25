import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/search_provider.dart';
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

                return SingleChildScrollView(
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
}
