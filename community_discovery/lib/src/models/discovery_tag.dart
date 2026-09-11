class DiscoveryTag {
  const DiscoveryTag({
    required this.id,
    required this.name,
    required this.type,
  });

  final int id;
  final String name;
  final String type;

  factory DiscoveryTag.fromMap(Map<String, dynamic> map) => DiscoveryTag(
    id: (map['id'] as num).toInt(),
    name: map['name'] as String,
    type: map['tag_type'] as String? ?? 'general',
  );
}
