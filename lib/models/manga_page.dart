import 'dart:developer' as developer;

class MangaPage {
  final String baseUrl;
  final List<String> pageUrls;

  const MangaPage({
    required this.baseUrl,
    required this.pageUrls,
  });

  factory MangaPage.fromJson(Map<String, dynamic> json) {
    try {
      final baseUrl = json['baseUrl'] as String;
      if (baseUrl == 'file://') {
        final urls = (json['pageUrls'] as List<dynamic>).cast<String>();
        return MangaPage(
          baseUrl: baseUrl,
          pageUrls: urls,
        );
      }

      final chapter = json['chapter'] as Map<String, dynamic>;
      final hash = chapter['hash'] as String;
      final pages = chapter['data'] as List<dynamic>;

      final pageUrls = pages.map((page) => 
        '$baseUrl/data/$hash/$page'
      ).toList();

      return MangaPage(
        baseUrl: baseUrl,
        pageUrls: pageUrls,
      );
    } catch (e, stackTrace) {
      developer.log('Error parsing manga page: $e\n$stackTrace');
      rethrow;
    }
  }

  int get pageCount => pageUrls.length;

  String getPageUrl(int index) {
    if (index < 0 || index >= pageUrls.length) {
      throw RangeError('Page index out of range: $index');
    }
    return pageUrls[index];
  }

  Map<String, dynamic> toJson() {
    if (baseUrl == 'file://') {
      return {
        'baseUrl': baseUrl,
        'pageUrls': pageUrls,
      };
    }

    // Extract hash and filenames from the URLs to reconstruct the structure
    // that matches what we receive from the API
    final firstUrl = pageUrls.isNotEmpty ? pageUrls[0] : '';
    final urlParts = firstUrl.split('/');
    
    String hash = '';
    if (urlParts.length >= 2) {
      // The hash is typically the second-to-last part in the URL path
      hash = urlParts[urlParts.length - 2];
    }
    
    // Extract filenames from the URLs
    final data = pageUrls.map((url) {
      final parts = url.split('/');
      return parts.isNotEmpty ? parts.last : '';
    }).toList();
    
    return {
      'baseUrl': baseUrl,
      'chapter': {
        'hash': hash,
        'data': data,
      }
    };
  }
}
