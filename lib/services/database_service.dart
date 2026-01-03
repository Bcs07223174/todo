import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/task.dart';

class DatabaseService {
  final String uid;
  DatabaseService({required this.uid});

  final CollectionReference taskCollection = FirebaseFirestore.instance
      .collection('tasks');

  Future<void> addTask(Task task) async {
    return await taskCollection.doc(task.id).set(task.toMap());
  }

  Future<void> updateTask(Task task) async {
    return await taskCollection.doc(task.id).update(task.toMap());
  }

  Future<void> deleteTask(String taskId) async {
    return await taskCollection.doc(taskId).delete();
  }

  Stream<List<Task>> get tasks {
    return taskCollection
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map(_taskListFromSnapshot);
  }

  List<Task> _taskListFromSnapshot(QuerySnapshot snapshot) {
    return snapshot.docs.map((doc) {
      return Task.fromMap(doc.data() as Map<String, dynamic>);
    }).toList();
  }
}
