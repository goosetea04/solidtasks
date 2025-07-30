class Task {
  final String id;            
  String title;
  bool isDone;
  DateTime createdAt;
  DateTime? dueDate;
  DateTime updatedAt;

  Task({
    required this.id,
    required this.title,
    this.isDone = false,
    DateTime? createdAt,
    this.dueDate,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isDone': isDone,
        'createdAt': createdAt.toIso8601String(),
        'dueDate': dueDate?.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'],
        title: json['title'],
        isDone: json['isDone'] as bool,
        createdAt: DateTime.parse(json['createdAt']),
        dueDate: json['dueDate'] == null ? null : DateTime.parse(json['dueDate']),
        updatedAt: DateTime.parse(json['updatedAt']),
      );
}