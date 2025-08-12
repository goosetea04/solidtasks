class SharedEntry {
  final String url;
  final String ownerWebId;
  final String permissionsRaw;
  final bool isLikelyTask;
  SharedEntry({
    required this.url,
    required this.ownerWebId,
    required this.permissionsRaw,
    required this.isLikelyTask,
  });

  String get name {
    final segs = Uri.parse(url).pathSegments;
    return segs.isNotEmpty ? segs.last : url;
  }
}