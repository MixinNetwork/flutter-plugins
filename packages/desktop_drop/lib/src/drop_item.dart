class WebDropItem {
  WebDropItem({
    required this.uri,
    required this.name,
    required this.type,
    required this.size,
    required this.relativePath,
    required this.lastModified,
  });

  final String uri;
  final String name;
  final String type;
  final int size;
  final String? relativePath;
  final DateTime lastModified;

  factory WebDropItem.fromJson(Map<String, dynamic> json) => WebDropItem(
        uri: json['uri'],
        name: json['name'],
        type: json['type'],
        size: json['size'],
        relativePath: json['relativePath'],
        lastModified: DateTime.fromMillisecondsSinceEpoch(json['lastModified']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'uri': uri,
        'name': name,
        'type': type,
        'size': size,
        'relativePath': relativePath,
        'lastModified': lastModified.millisecondsSinceEpoch,
      };
}
