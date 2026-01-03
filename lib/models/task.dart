class Task {
  final String id;
  String title;
  String description;
  bool isCompleted;
  DateTime dueDate;
  final String userId;
  String? imageUrl;
  String priority;
  String category;

  Task({
    required this.id,
    required this.title,
    required this.description,
    this.isCompleted = false,
    required this.dueDate,
    required this.userId,
    this.imageUrl,
    this.priority = 'Medium',
    this.category = 'General',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'isCompleted': isCompleted,
      'dueDate': dueDate.toIso8601String(),
      'userId': userId,
      'imageUrl': imageUrl,
      'priority': priority,
      'category': category,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      isCompleted: map['isCompleted'] ?? false,
      dueDate: DateTime.parse(map['dueDate']),
      userId: map['userId'] ?? '',
      imageUrl: map['imageUrl'],
      priority: map['priority'] ?? 'Medium',
      category: map['category'] ?? 'General',
    );
  }
}
