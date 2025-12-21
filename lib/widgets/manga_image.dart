import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb;

class MangaImage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // For empty URLs, show a placeholder
    if (imageUrl.isEmpty) {
      return _buildPlaceholder('No Image');
    }

    // Use placeholder.com images directly with better error handling
    if (imageUrl.contains('placeholder.com')) {
      // Extract the text from the placeholder URL to show as fallback
      String text = 'Manga';
      if (imageUrl.contains('text=')) {
        text = imageUrl.split('text=').last.replaceAll('+', ' ');
      }
      
      return Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildLoadingPlaceholder();
        },
        errorBuilder: (_, __, ___) => _buildPlaceholder(text),
      );
    }

    // For web platform, use a different approach to avoid CORS issues
    if (kIsWeb) {
      // For problematic domains that often cause CORS issues, use a placeholder
      if (imageUrl.contains('2xstorage.com') || 
          imageUrl.contains('xfs.io') || 
          imageUrl.contains('mangakakalot') ||
          imageUrl.contains('mangadex')) {
        
        // Generate a placeholder with the manga title
        final title = _extractTitleFromUrl(imageUrl);
        final placeholderUrl = 'https://via.placeholder.com/300x450/3498db/ffffff?text=${title.replaceAll(' ', '+')}';
        
        return Image.network(
          placeholderUrl,
          width: width,
          height: height,
          fit: fit,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _buildLoadingPlaceholder();
          },
          errorBuilder: (_, __, ___) => _buildPlaceholder(title),
        );
      }
    }

    // For all other cases, try to load the image directly with better error handling
    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
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
      width: width,
      height: height,
      color: Colors.grey[300],
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context) {
    // Log the error for debugging
    developer.log('Error loading image: $imageUrl', name: 'MangaImage');
    
    // Use a local asset as fallback instead of relying on external placeholder service
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_rounded,
            size: (height ?? 0) * 0.3,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 8),
          Text(
            'Image not available',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(String title) {
    return Container(
      width: width,
      height: height,
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
            size: (height ?? 0) * 0.3,
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
