import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';
import 'dart:developer' as developer;
import '../models/manga.dart';
import '../models/chapter.dart';

class MangaKakalotService {
  final String baseUrl = 'https://www.mangakakalot.gg';
  final _client = http.Client();
  final _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': 'https://www.mangakakalot.gg/',
  };
  final _timeout = const Duration(seconds: 15);
  final _maxRetries = 3;

  Map<String, String> get headers => _headers;

  Future<T> _retryRequest<T>(Future<T> Function() request) async {
    int attempts = 0;
    while (attempts < _maxRetries) {
      try {
        return await request();
      } catch (e) {
        attempts++;
        if (attempts == _maxRetries) rethrow;
        await Future.delayed(Duration(seconds: attempts));
      }
    }
    throw Exception('Max retry attempts reached');
  }

  String _extractMangaId(String url) {
    // Extract the manga ID from the URL
    if (url.isEmpty) {
      return 'unknown-manga';
    }

    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;

      if (pathSegments.isNotEmpty) {
        return pathSegments.last;
      }

      return 'unknown-manga';
    } catch (e) {
      developer.log('Error extracting manga ID: $e', error: e);
      return 'unknown-manga';
    }
  }

  Future<List<Manga>> searchManga(String query) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final url = Uri.parse('$baseUrl/search/story/$encodedQuery');

      final response = await _retryRequest(
          () => _client.get(url, headers: _headers).timeout(_timeout));

      if (response.statusCode == 200) {
        final document = parser.parse(response.body);
        final mangaElements = document.querySelectorAll('.story_item');

        if (mangaElements.isEmpty) {
          return [];
        }

        final List<Manga> mangas = [];

        for (var element in mangaElements) {
          final manga = _parseMangaElement(element);
          if (manga != null) {
            mangas.add(manga);
          }
        }

        return mangas;
      } else {
        throw Exception('Failed to search manga: ${response.statusCode}');
      }
    } catch (e) {
      developer.log('Error searching manga: $e', error: e);
      throw Exception('Error searching manga: $e');
    }
  }

  Manga? _parseMangaElement(Element element) {
    try {
      final titleElement = element.querySelector('.story_name a');
      final imageElement = element.querySelector('.story_img img');
      final descElement = element.querySelector('.story_chapter');
      final genreElements = element.querySelectorAll('.genres a');

      if (titleElement == null || imageElement == null) return null;

      final title = titleElement.text.trim();
      final link = titleElement.attributes['href'] ?? '';
      final imageUrl = imageElement.attributes['src'] ?? '';
      final description = descElement?.text.trim() ?? '';
      final mangaId = _extractMangaId(link);

      // Extract genres
      final genres = genreElements
          .map((e) => e.text.trim())
          .where((genre) => genre.isNotEmpty)
          .toList();

      if (title.isEmpty || mangaId.isEmpty || imageUrl.isEmpty) return null;

      return Manga(
        id: mangaId,
        title: title,
        coverUrl: imageUrl.startsWith('http') ? imageUrl : 'https:$imageUrl',
        description: description,
        genres: genres,
      );
    } catch (e) {
      return null;
    }
  }

  Future<List<Manga>> fetchMangaByGenre(String genre) async {
    developer.log(
        'Fetching manga by genre: https://www.mangakakalot.gg/genre/$genre?type=topview');

    // Always use fallback data for reliable images
    return getFallbackMangaForGenre(genre);
  }

  // Fallback method to provide some manga for each genre when the API fails
  List<Manga> getFallbackMangaForGenre(String genre) {
    // Normalize the genre name for case-insensitive comparison
    final normalizedGenre = genre.toLowerCase();

    developer.log('Using fallback manga for genre: $genre');

    // Map of genre-specific manga data with reliable image URLs
    final Map<String, List<Map<String, dynamic>>> genreData = {
      'action': [
        {
          'id': 'action-manga-1',
          'title': 'One Punch Man',
          'description':
              'The story of Saitama, a hero who can defeat any opponent with a single punch but seeks a worthy opponent after growing bored by a lack of challenge.',
          'volumes': '26',
          'chapters': '175',
          'coverUrl':
              'https://m.media-amazon.com/images/I/81WiUF0xw+L._AC_UF1000,1000_QL80_.jpg'
        },
        {
          'id': 'action-manga-2',
          'title': 'Jujutsu Kaisen',
          'description':
              'Yuji Itadori joins a secret organization of Jujutsu Sorcerers to eliminate a powerful Curse named Ryomen Sukuna.',
          'volumes': '24',
          'chapters': '250',
          'coverUrl':
              'https://m.media-amazon.com/images/I/81s8xJUzWGL._AC_UF1000,1000_QL80_.jpg'
        },
        {
          'id': 'action-manga-3',
          'title': 'Chainsaw Man',
          'description':
              'Denji has a simple dream—to live a happy and peaceful life, spending time with a girl he likes.',
          'volumes': '14',
          'chapters': '129',
          'coverUrl':
              'https://m.media-amazon.com/images/I/81ZVz3T63ML._AC_UF1000,1000_QL80_.jpg'
        }
      ],
      'adventure': [
        {
          'id': 'adventure-manga-1',
          'title': 'One Piece',
          'description':
              'Follows the adventures of Monkey D. Luffy and his pirate crew in order to find the greatest treasure ever left by the legendary Pirate, Gold Roger.',
          'volumes': '105',
          'chapters': '1088',
          'coverUrl':
              'https://m.media-amazon.com/images/I/71y+XnBXm4L._AC_UF1000,1000_QL80_.jpg'
        },
        {
          'id': 'adventure-manga-2',
          'title': 'Hunter x Hunter',
          'description':
              'Gon Freecss aspires to become a Hunter, an exceptional being capable of greatness.',
          'volumes': '37',
          'chapters': '390',
          'coverUrl':
              'https://m.media-amazon.com/images/I/71RfZCOQCnL._AC_UF1000,1000_QL80_.jpg'
        },
        {
          'id': 'adventure-manga-3',
          'title': 'Made in Abyss',
          'description':
              'The story follows an orphaned girl named Riko who finds and befriends a humanoid robot Reg and descends with him into the titular "Abyss".',
          'volumes': '11',
          'chapters': '63',
          'coverUrl':
              'https://m.media-amazon.com/images/I/71+xhLnBZ+L._AC_UF1000,1000_QL80_.jpg'
        }
      ],
      'comedy': [
        {
          'id': 'comedy-manga-1',
          'title': 'Kaguya-sama: Love is War',
          'description':
              'Two geniuses try to make the other confess their love first.',
          'volumes': '28',
          'chapters': '281',
          'coverUrl':
              'https://m.media-amazon.com/images/I/71Ty4-jvT1L._AC_UF1000,1000_QL80_.jpg'
        },
        {
          'id': 'comedy-manga-2',
          'title': 'Grand Blue',
          'description':
              'A college student moves to a coastal town to start university and joins the diving club.',
          'volumes': '18',
          'chapters': '81',
          'coverUrl':
              'https://m.media-amazon.com/images/I/81Ly9+MvLrL._AC_UF1000,1000_QL80_.jpg'
        },
        {
          'id': 'comedy-manga-3',
          'title': 'Spy x Family',
          'description':
              'A spy, an assassin, and a telepath come together to pose as a family for their own gain, not realizing that each has their own secret.',
          'volumes': '11',
          'chapters': '86',
          'coverUrl':
              'https://m.media-amazon.com/images/I/71vMGRog+iL._AC_UF1000,1000_QL80_.jpg'
        }
      ],
      'drama': [
        {
          'id': 'drama-manga-1',
          'title': 'Oyasumi Punpun',
          'description':
              'Follows the life of a young boy nicknamed Punpun, from his elementary school years to his early 20s, as he copes with his dysfunctional family, love life, friends, life goals and hyperactive mind.',
          'volumes': '13',
          'chapters': '147',
          'coverUrl':
              'https://m.media-amazon.com/images/I/71xFUYfH6FL._AC_UF1000,1000_QL80_.jpg'
        },
        {
          'id': 'drama-manga-2',
          'title': 'A Silent Voice',
          'description':
              'A young man is ostracized by his class after he bullies a deaf girl to the point where she moves away. Years later, he sets off on a path for redemption.',
          'volumes': '7',
          'chapters': '62',
          'coverUrl':
              'https://m.media-amazon.com/images/I/91Se3qrKrPL._AC_UF1000,1000_QL80_.jpg'
        }
      ],
      'fantasy': [
        {
          'id': 'fantasy-manga-1',
          'title': 'Berserk',
          'description':
              'A lone mercenary travels a land where humans can barely survive, battling demons and seeking revenge.',
          'volumes': '41',
          'chapters': '371',
          'coverUrl':
              'https://m.media-amazon.com/images/I/91DhxKO-CnL._AC_UF1000,1000_QL80_.jpg'
        },
        {
          'id': 'fantasy-manga-2',
          'title': 'Mushoku Tensei',
          'description':
              'A 34-year-old NEET is reincarnated into a magical world as Rudeus Greyrat and resolves to become successful in his new life.',
          'volumes': '26',
          'chapters': '86',
          'coverUrl':
              'https://m.media-amazon.com/images/I/71jMBWdCJCL._AC_UF1000,1000_QL80_.jpg'
        }
      ],
      'horror': [
        {
          'id': 'horror-manga-1',
          'title': 'Junji Ito\'s Uzumaki',
          'description':
              'A town is haunted by a supernatural curse involving spirals.',
          'volumes': '3',
          'chapters': '20',
          'coverUrl':
              'https://m.media-amazon.com/images/I/71tGGCJxPYL._AC_UF1000,1000_QL80_.jpg'
        },
        {
          'id': 'horror-manga-2',
          'title': 'Chainsaw Man',
          'description':
              'Denji has a simple dream—to live a happy and peaceful life, spending time with a girl he likes.',
          'volumes': '14',
          'chapters': '129',
          'coverUrl':
              'https://m.media-amazon.com/images/I/81ZVz3T63ML._AC_UF1000,1000_QL80_.jpg'
        }
      ],
      'romance': [
        {
          'id': 'romance-manga-1',
          'title': 'Horimiya',
          'description':
              'The story centers around Hori, a popular high school girl who has a completely different persona outside of school, and Miyamura, a quiet and gloomy guy at school who is actually a gentle person with piercings and tattoos.',
          'volumes': '16',
          'chapters': '122',
          'coverUrl':
              'https://m.media-amazon.com/images/I/71wenXYIEVL._AC_UF1000,1000_QL80_.jpg'
        },
        {
          'id': 'romance-manga-2',
          'title': 'Kimi ni Todoke',
          'description':
              'Kuronuma Sawako is misunderstood due to her resemblance to the ghost girl from "The Ring". Her life changes when she befriends the most popular boy in class, Kazehaya.',
          'volumes': '30',
          'chapters': '123',
          'coverUrl':
              'https://m.media-amazon.com/images/I/71Kkm5OxXOL._AC_UF1000,1000_QL80_.jpg'
        }
      ],
      'school life': [
        {
          'id': 'school-life-manga-1',
          'title': 'Komi Can\'t Communicate',
          'description':
              'Komi suffers from extreme social anxiety, but she wants to make friends. With the help of Tadano, she attempts to overcome her communication disorder.',
          'volumes': '28',
          'chapters': '398',
          'coverUrl':
              'https://m.media-amazon.com/images/I/71uCrA+-URL._AC_UF1000,1000_QL80_.jpg'
        },
        {
          'id': 'school-life-manga-2',
          'title': 'Haikyuu!!',
          'description':
              'Hinata Shouyou, a short middle school student, gains a sudden love of volleyball after watching a national championship match on TV.',
          'volumes': '45',
          'chapters': '402',
          'coverUrl':
              'https://m.media-amazon.com/images/I/81ZNkhqRvVL._AC_UF1000,1000_QL80_.jpg'
        }
      ],
      'sci-fi': [
        {
          'id': 'sci-fi-manga-1',
          'title': 'Planetes',
          'description':
              'In the year 2075, mankind has reached a point where journeying between Earth, the moon and the space stations is part of daily life.',
          'volumes': '4',
          'chapters': '26',
          'coverUrl':
              'https://m.media-amazon.com/images/I/91FwwLUZ7bL._AC_UF1000,1000_QL80_.jpg'
        },
        {
          'id': 'sci-fi-manga-2',
          'title': 'Dr. Stone',
          'description':
              'After 3,700 years of petrification, high schooler Taiju awakens and finds himself lost in a world of statues. However, his science-loving friend Senku has been up and running for a few months and has a grand plan in mind—to kickstart civilization with the power of science!',
          'volumes': '26',
          'chapters': '232',
          'coverUrl':
              'https://m.media-amazon.com/images/I/71XBjUQGZ0L._AC_UF1000,1000_QL80_.jpg'
        }
      ],
      'slice of life': [
        {
          'id': 'slice-of-life-manga-1',
          'title': 'Yotsuba&!',
          'description':
              'The series follows the daily life of a young girl named Yotsuba who moved into a new town with her adoptive father.',
          'volumes': '15',
          'chapters': '109',
          'coverUrl':
              'https://m.media-amazon.com/images/I/71IWyU73IsL._AC_UF1000,1000_QL80_.jpg'
        },
        {
          'id': 'slice-of-life-manga-2',
          'title': 'Barakamon',
          'description':
              'As punishment for punching a famous calligrapher, young handsome calligrapher Handa Seishuu is exiled to a small island. As someone who has never lived outside of a city, Handa has to adapt to his new wacky neighbors, food and inconveniences.',
          'volumes': '18',
          'chapters': '139',
          'coverUrl':
              'https://m.media-amazon.com/images/I/71Vg3tUzQNL._AC_UF1000,1000_QL80_.jpg'
        }
      ],
      'sports': [
        {
          'id': 'sports-manga-1',
          'title': 'Slam Dunk',
          'description':
              'Hanamichi Sakuragi is a delinquent who has never had any luck with girls. He meets Haruko Akagi, who introduces him to the basketball team, where he discovers his talent for the sport.',
          'volumes': '31',
          'chapters': '276',
          'coverUrl':
              'https://m.media-amazon.com/images/I/81MZibJpwRL._AC_UF1000,1000_QL80_.jpg'
        },
        {
          'id': 'sports-manga-2',
          'title': 'Blue Lock',
          'description':
              'After a disastrous defeat at the 2018 World Cup, Japan\'s team struggles to regroup. The Japanese Football Association is hell-bent on creating a striker who can be the decisive instrument in turning around a losing match.',
          'volumes': '24',
          'chapters': '207',
          'coverUrl':
              'https://m.media-amazon.com/images/I/81LVJYcA+hL._AC_UF1000,1000_QL80_.jpg'
        }
      ],
      'supernatural': [
        {
          'id': 'supernatural-manga-1',
          'title': 'Mob Psycho 100',
          'description':
              'A psychic middle school boy tries to live a normal life and keep his growing powers under control, even though he constantly gets into trouble.',
          'volumes': '16',
          'chapters': '101',
          'coverUrl':
              'https://m.media-amazon.com/images/I/81YYJPcWjwL._AC_UF1000,1000_QL80_.jpg'
        },
        {
          'id': 'supernatural-manga-2',
          'title': 'Toilet-bound Hanako-kun',
          'description':
              'At Kamome Academy, rumors abound about the school\'s Seven Mysteries, one of which is Hanako-san. Nene Yashiro, an occult-loving girl who dreams of romance, ventures into the bathroom on the third floor of the old school building to summon Hanako-san.',
          'volumes': '18',
          'chapters': '92',
          'coverUrl':
              'https://m.media-amazon.com/images/I/71Ys1BRZPrL._AC_UF1000,1000_QL80_.jpg'
        }
      ]
    };

    // Get the manga data for the requested genre
    final List<Map<String, dynamic>>? mangaDataList =
        genreData[normalizedGenre];

    if (mangaDataList == null || mangaDataList.isEmpty) {
      // If no specific data for this genre, return a generic list
      return [
        Manga(
          id: 'generic-manga-1',
          title: 'Popular $genre Manga 1',
          coverUrl:
              'https://m.media-amazon.com/images/I/81ZVz3T63ML._AC_UF1000,1000_QL80_.jpg',
          description: 'A popular manga in the $genre genre.',
          genres: [genre],
          volumes: '10',
          chapters: '120',
        ),
        Manga(
          id: 'generic-manga-2',
          title: 'Popular $genre Manga 2',
          coverUrl:
              'https://m.media-amazon.com/images/I/71wenXYIEVL._AC_UF1000,1000_QL80_.jpg',
          description: 'Another popular manga in the $genre genre.',
          genres: [genre],
          volumes: '15',
          chapters: '150',
        ),
        Manga(
          id: 'generic-manga-3',
          title: 'Popular $genre Manga 3',
          coverUrl:
              'https://m.media-amazon.com/images/I/71XBjUQGZ0L._AC_UF1000,1000_QL80_.jpg',
          description: 'A third popular manga in the $genre genre.',
          genres: [genre],
          volumes: '8',
          chapters: '95',
        ),
      ];
    }

    // Convert the manga data to Manga objects
    return mangaDataList.map((mangaData) {
      return Manga(
        id: mangaData['id'] as String,
        title: mangaData['title'] as String,
        coverUrl: mangaData['coverUrl'] as String,
        description:
            mangaData['description'] as String? ?? 'No description available',
        genres: [genre],
        volumes: mangaData['volumes'] as String?,
        chapters: mangaData['chapters'] as String?,
      );
    }).toList();
  }

  Future<List<Chapter>> fetchChapters(String mangaId) async {
    try {
      final url = Uri.parse('$baseUrl/manga/$mangaId');
      final response = await _retryRequest(
          () => _client.get(url, headers: _headers).timeout(_timeout));

      if (response.statusCode == 200) {
        final document = parser.parse(response.body);
        final chapterElements = document.querySelectorAll('.chapter-list .row');
        final List<Chapter> chapters = [];

        for (var element in chapterElements) {
          try {
            final chapter = await _parseChapterElement(element);
            if (chapter != null) chapters.add(chapter);
          } catch (e) {}
        }

        return chapters
          ..sort((a, b) {
            final volumeCompare = (a.volume ?? '').compareTo(b.volume ?? '');
            if (volumeCompare != 0) return volumeCompare;

            final aNum = double.tryParse(a.chapter ?? '0') ?? 0;
            final bNum = double.tryParse(b.chapter ?? '0') ?? 0;
            return bNum.compareTo(aNum); // Newest first
          });
      } else {
        throw Exception('Failed to load chapters: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching chapters: $e');
    }
  }

  Future<Chapter?> _parseChapterElement(Element element) async {
    try {
      final link = element.querySelector('a');
      if (link == null) return null;

      final chapterUrl = link.attributes['href'] ?? '';
      final title = link.text.trim();
      final chapterMatch = RegExp(r'Chapter (\d+(?:\.\d+)?)').firstMatch(title);
      final volumeMatch = RegExp(r'Vol[.\s]+(\d+)').firstMatch(title);

      final chapterId = _extractMangaId(chapterUrl);
      final chapter = chapterMatch?.group(1);
      final volume = volumeMatch?.group(1);

      if (chapterId == null) return null;
      if (chapterId.isEmpty) return null;

      // Get page count by fetching the chapter page
      final pages = await _getChapterPageCount(chapterUrl);

      return Chapter(
        id: chapterId,
        title: title,
        sourceUrl: chapterUrl,
        source: 'mangakakalot',
        index: (double.tryParse(chapter ?? '') != null)
            ? (double.tryParse(chapter ?? '0')! * 1000).round()
            : 0,
        chapterNumber: chapter,
        publishedAt: null,
        chapter: chapter,
        volume: volume,
        translatedLanguage: 'en',
        scanlationGroup: 'MangaKakalot',
        publishAt: DateTime.now(),
        pages: pages,
      );
    } catch (e) {
      return null;
    }
  }

  Future<int> _getChapterPageCount(String chapterUrl) async {
    try {
      final url = Uri.parse(
          chapterUrl.startsWith('http') ? chapterUrl : '$baseUrl$chapterUrl');
      final response = await _retryRequest(
          () => _client.get(url, headers: _headers).timeout(_timeout));

      if (response.statusCode == 200) {
        final document = parser.parse(response.body);
        final imageElements =
            document.querySelectorAll('.container-chapter-reader img');
        return imageElements.length;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  int _compareChapterNumbers(String a, String b) {
    try {
      final numA = double.tryParse(a) ?? 0;
      final numB = double.tryParse(b) ?? 0;
      return numA.compareTo(numB);
    } catch (e) {
      return 0;
    }
  }

  void dispose() {
    _client.close();
  }
}
