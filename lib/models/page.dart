class MangaPage {
  final String id;
  final String imageUrl;
  final int number;

  MangaPage({
    required this.id,
    required this.imageUrl,
    required this.number,
  });

  factory MangaPage.fromJson(Map<String, dynamic> json, String baseUrl) {
    return MangaPage(
      id: json['id'] ?? '',
      imageUrl: '$baseUrl${json['attributes']['fileName']}',
      number: int.tryParse(json['attributes']['number'] ?? '') ?? 0,
    );
  }
}
