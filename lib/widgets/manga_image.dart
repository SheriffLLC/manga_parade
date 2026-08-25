import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class MangaImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;

  const MangaImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  State<MangaImage> createState() => _MangaImageState();
}

class _MangaImageState extends State<MangaImage> {
  int _retryKey = 0;

  void _reload() {
    setState(() {
      _retryKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // For empty URLs, show a placeholder
    if (widget.imageUrl.isEmpty) {
      return _buildPlaceholder('No Image');
    }

    // Use placeholder.com images directly with better error handling
    if (widget.imageUrl.contains('placeholder.com')) {
      return Image.network(
        widget.imageUrl,
        key: ValueKey(_retryKey),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildLoadingPlaceholder();
        },
        errorBuilder: (_, __, ___) => _buildErrorWidget(context),
      );
    }

    // For web platform, use a different approach to avoid CORS issues
    if (kIsWeb) {
      // For problematic domains that often cause CORS issues, use a placeholder
      if (widget.imageUrl.contains('2xstorage.com') || 
          widget.imageUrl.contains('xfs.io') || 
          widget.imageUrl.contains('mangakakalot') ||
          widget.imageUrl.contains('mangadex')) {
        
        // Generate a placeholder with the manga title
        final title = _extractTitleFromUrl(widget.imageUrl);
        final placeholderUrl = 'https://via.placeholder.com/300x450/3498db/ffffff?text=${title.replaceAll(' ', '+')}';
        
        return Image.network(
          placeholderUrl,
          key: ValueKey(_retryKey),
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _buildLoadingPlaceholder();
          },
          errorBuilder: (_, __, ___) => _buildErrorWidget(context),
        );
      }
    }

    final bool isLocal = widget.imageUrl.startsWith('file://') ||
        (!widget.imageUrl.startsWith('http://') && !widget.imageUrl.startsWith('https://'));

    if (isLocal) {
      final cleanPath = widget.imageUrl.startsWith('file://') ? widget.imageUrl.substring(7) : widget.imageUrl;
      return Image.file(
        File(cleanPath),
        key: ValueKey(_retryKey),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (_, __, ___) {
          return _buildErrorWidget(context);
        },
      );
    }

    // For all other cases, try to load the image directly with better error handling
    return Image.network(
      widget.imageUrl,
      key: ValueKey(_retryKey),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _buildLoadingPlaceholder();
      },
      errorBuilder: (_, __, ___) {
        // If image fails to load, use a local placeholder
        return _buildErrorWidget(context);
      },
    );
  }

  String _extractTitleFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      
      if (pathSegments.isNotEmpty) {
        final lastSegment = pathSegments.last;
        if (lastSegment.contains('.')) {
          // Remove file extension
          final title = lastSegment.split('.').first;
          return _formatTitle(title);
        }
        return _formatTitle(lastSegment);
      }
    } catch (e) {
      // Ignore parsing errors
    }
    
    return 'Manga';
  }

  String _formatTitle(String title) {
    // Replace dashes and underscores with spaces
    title = title.replaceAll('-', ' ').replaceAll('_', ' ');
    
    // Capitalize words
    final words = title.split(' ');
    final capitalizedWords = words.map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1);
    });
    
    return capitalizedWords.join(' ');
  }

  Widget _buildLoadingPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[900],
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context) {
    // Log the error for debugging
    developer.log('Error loading image: ${widget.imageUrl}', name: 'MangaImage');
    
    // Use a local asset as fallback instead of relying on external placeholder service
    return Center(
      child: Container(
        width: widget.width ?? double.infinity,
        height: widget.height ?? 300,
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

  Widget _buildPlaceholder(String title) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.blue[100],
        border: Border.all(color: Colors.blue[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image,
            size: (widget.height ?? 0) * 0.3,
            color: Colors.blue[700],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue[900],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
