class SharedEntry {
  final String url;
  final String ownerWebId;
  final String permissionsRaw;
  final bool isLikelyTask;
  final String? description;

  SharedEntry({
    required this.url,
    required this.ownerWebId,
    required this.permissionsRaw,
    required this.isLikelyTask,
    this.description,
  });

  String get name {
    final segs = Uri.parse(url).pathSegments;
    return segs.isNotEmpty ? segs.last : url;
  }
}
