class M3uProvider {
  final String id;
  final String name;
  final String url;

  const M3uProvider({required this.id, required this.name, required this.url});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'url': url};

  factory M3uProvider.fromJson(Map<String, dynamic> json) => M3uProvider(
    id: json['id'] as String,
    name: json['name'] as String,
    url: json['url'] as String,
  );
}
