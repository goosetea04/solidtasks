class Task {
  final String id;
  String title;
  bool isDone;
  DateTime? dueDate;
  String? description;
  DateTime createdAt;
  DateTime updatedAt; 

  Task({
    required this.id,
    required this.title,
    this.isDone = false,
    this.dueDate,
    this.description,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'isDone': isDone,
      'dueDate': dueDate?.toIso8601String(),
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      title: json['title'] as String,
      isDone: json['isDone'] as bool? ?? false,
      dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate']) : null,
      description: json['description'] as String?,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : DateTime.now(),
    );
  }

  // Sentinel to allow explicit null (clear) vs no change
  static const Object _noChange = Object();

  Task copyWith({
    String? title,
    bool? isDone,
    DateTime? dueDate,
    Object? description = _noChange, // use Object? not String?
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
      dueDate: dueDate ?? this.dueDate,
      description: identical(description, _noChange)
          ? this.description
          : description as String?, // can set to null to clear
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
