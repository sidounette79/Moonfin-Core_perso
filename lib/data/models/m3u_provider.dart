class M3uProvider {
  final String id;
  final String name;
  final String url;

  /// Optional XMLTV guide URL for this playlist - most public/shared M3U
  /// lists ship without embedded EPG, and providers that do publish a guide
  /// serve it as a separate XMLTV feed rather than inline in the playlist.
  /// Null means "no EPG for this provider's channels" (unchanged from
  /// before this field existed).
  final String? epgUrl;

  const M3uProvider({
    required this.id,
    required this.name,
    required this.url,
    this.epgUrl,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    if (epgUrl != null) 'epgUrl': epgUrl,
  };

  factory M3uProvider.fromJson(Map<String, dynamic> json) => M3uProvider(
    id: json['id'] as String,
    name: json['name'] as String,
    url: json['url'] as String,
    epgUrl: json['epgUrl'] as String?,
  );
}
