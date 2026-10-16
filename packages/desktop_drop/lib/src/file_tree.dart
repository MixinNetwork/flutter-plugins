// Windows virtual files use relative descriptor names. Build their tree
// without treating those names as filesystem paths or writing any files.
List<Map> fileTree(List<Map> files) {
  final roots = <Map>[];
  final directories = <String, Map>{};
  for (final file in files) {
    final virtualPath = file['virtualPath'] as String?;
    if (virtualPath == null) {
      roots.add(file);
      continue;
    }
    final parts = virtualPath
        .split(RegExp(r'[/\\]'))
        .where((part) => part.isNotEmpty && part != '.')
        .toList();
    if (parts.isEmpty || parts.contains('..')) {
      throw FormatException('Invalid virtual file name: $virtualPath');
    }
    var children = roots;
    var key = '';
    for (var i = 0; i < parts.length; i++) {
      key += '/${parts[i]}';
      if (i == parts.length - 1 && file['isDirectory'] != true) {
        children.add({...file, 'name': parts[i]});
      } else {
        final directory = directories.putIfAbsent(key, () {
          final value = <Object?, Object?>{
            'name': parts[i],
            'isDirectory': true,
            'isPromised': true,
            'children': <Map>[],
          };
          children.add(value);
          return value;
        });
        children = directory['children'] as List<Map>;
      }
    }
  }
  return roots;
}
