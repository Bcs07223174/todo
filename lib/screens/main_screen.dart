import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' hide Task;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:neon_task/screens/dashboard_screen.dart';
import 'package:neon_task/screens/home_screen.dart';
import 'package:neon_task/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/task.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../theme/colors.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  List<Task> _tasks = [];
  int _xp = 0;
  int _level = 1;
  StreamSubscription<List<Task>>? _tasksSubscription;

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    _setupFirestoreListener();
  }

  @override
  void dispose() {
    _tasksSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load XP and Level
    setState(() {
      _xp = prefs.getInt('user_xp') ?? 0;
      _level = prefs.getInt('user_level') ?? 1;
    });

    final String? tasksJson = prefs.getString('local_tasks');
    if (tasksJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(tasksJson);
        setState(() {
          _tasks = decoded
              .map((e) => Task.fromMap(Map<String, dynamic>.from(e)))
              .toList();
        });
      } catch (e) {
        debugPrint('Error loading local tasks: $e');
      }
    }
  }

  Future<void> _saveLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_tasks.map((t) => t.toMap()).toList());
    await prefs.setString('local_tasks', encoded);
    await prefs.setInt('user_xp', _xp);
    await prefs.setInt('user_level', _level);
  }

  void _setupFirestoreListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _tasksSubscription = DatabaseService(uid: user.uid).tasks.listen(
        (tasks) {
          setState(() {
            _tasks = tasks;
          });
          _saveLocalData();
        },
        onError: (error) {
          debugPrint('Firestore error: $error');
          // Fallback to local tasks is automatic since we don't overwrite _tasks on error
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Offline mode: $error'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      );
    }
  }

  Future<void> _addTask(
    String title,
    String description,
    DateTime dueDate,
    XFile? imageFile,
    String? providedImageUrl,
    String priority,
    String category,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    String? imageUrl = providedImageUrl;

    if (imageFile != null) {
      try {
        final ref = FirebaseStorage.instance
            .ref()
            .child('task_images')
            .child(user.uid)
            .child('$id.jpg');

        if (kIsWeb) {
          await ref.putData(await imageFile.readAsBytes());
        } else {
          await ref.putFile(File(imageFile.path));
        }

        imageUrl = await ref.getDownloadURL();
      } catch (e) {
        debugPrint('Error uploading image: $e');
      }
    }

    final newTask = Task(
      id: id,
      title: title,
      description: description,
      dueDate: dueDate,
      userId: user.uid,
      imageUrl: imageUrl,
      priority: priority,
      category: category,
    );

    // Optimistic update
    setState(() {
      _tasks.add(newTask);
    });
    _saveLocalData();

    try {
      await DatabaseService(uid: user.uid).addTask(newTask);
    } catch (e) {
      debugPrint('Error adding task to Firestore: $e');
    }

    NotificationService.scheduleNotification(
      id: id.hashCode,
      title: 'Task Reminder',
      body: title,
      scheduledDate: dueDate,
    );
  }

  void _deleteTask(String id) {
    final user = FirebaseAuth.instance.currentUser;

    // Optimistic update
    setState(() {
      _tasks.removeWhere((task) => task.id == id);
    });
    _saveLocalData();

    if (user != null) {
      DatabaseService(uid: user.uid).deleteTask(id).catchError((e) {
        debugPrint('Error deleting task from Firestore: $e');
      });
      NotificationService.cancel(id.hashCode);
    }
  }

  void _toggleTaskCompletion(Task task) {
    final user = FirebaseAuth.instance.currentUser;

    // Optimistic update
    setState(() {
      task.isCompleted = !task.isCompleted;
      if (task.isCompleted) {
        _xp += 10;
        if (_xp >= _level * 100) {
          _xp -= _level * 100;
          _level++;
          _showLevelUpDialog();
        }
      }
    });
    _saveLocalData();

    if (user != null) {
      DatabaseService(uid: user.uid).updateTask(task).catchError((e) {
        debugPrint('Error updating task in Firestore: $e');
      });

      if (task.isCompleted) {
        NotificationService.cancel(task.id.hashCode);
      }
    }
  }

  void _showLevelUpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.electricPurple,
        title: const Text('Level Up!', style: TextStyle(color: AppColors.pureWhite)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star, size: 64, color: Colors.amber),
            const SizedBox(height: 16),
            Text(
              'You reached Level $_level!',
              style: const TextStyle(color: AppColors.pureWhite, fontSize: 18),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Awesome!', style: TextStyle(color: AppColors.pureWhite)),
          ),
        ],
      ),
    );
  }

  void _editTask(
    Task task,
    String newTitle,
    String newDescription,
    DateTime newDueDate,
    String newPriority,
    String? newImageUrl,
    String newCategory,
  ) {
    final user = FirebaseAuth.instance.currentUser;

    // Optimistic update
    setState(() {
      task.title = newTitle;
      task.description = newDescription;
      task.dueDate = newDueDate;
      task.priority = newPriority;
      task.category = newCategory;
      if (newImageUrl != null) task.imageUrl = newImageUrl;
    });
    _saveLocalData();

    if (user != null) {
      DatabaseService(uid: user.uid).updateTask(task).catchError((e) {
        debugPrint('Error updating task in Firestore: $e');
      });

      NotificationService.cancel(task.id.hashCode);
      if (!task.isCompleted) {
        NotificationService.scheduleNotification(
          id: task.id.hashCode,
          title: 'Task Reminder',
          body: newTitle,
          scheduledDate: newDueDate,
        );
      }
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _showAddEditTaskDialog({Task? task}) async {
    final titleController = TextEditingController(text: task?.title ?? '');
    final descriptionController = TextEditingController(
      text: task?.description ?? '',
    );
    XFile? selectedImage;

    // Voice Input Setup
    final stt.SpeechToText speech = stt.SpeechToText();
    bool isListening = false;

    // Default to task's date or now
    DateTime selectedDate = task?.dueDate ?? DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(selectedDate);
    String selectedPriority = task?.priority ?? 'Medium';
    String selectedCategory = task?.category ?? 'General';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          void toggleListening() async {
            if (!isListening) {
              bool available = await speech.initialize(
                onStatus: (status) {
                  if (status == 'notListening') {
                    setState(() => isListening = false);
                  }
                },
                onError: (errorNotification) {
                  setState(() => isListening = false);
                  debugPrint('Speech Error: $errorNotification');
                },
              );
              if (available) {
                setState(() => isListening = true);
                speech.listen(
                  onResult: (result) {
                    final String spokenText = result.recognizedWords;
                    String title = spokenText;
                    DateTime newDate = selectedDate;
                    TimeOfDay newTime = selectedTime;
                    String newPriority = selectedPriority;

                    // Simple parsing logic
                    final lowerText = spokenText.toLowerCase();

                    // Priority parsing
                    if (lowerText.contains('high priority') ||
                        lowerText.contains('priority high')) {
                      newPriority = 'High';
                      title = title.replaceAll(
                          RegExp(r'\b(high priority|priority high)\b',
                              caseSensitive: false),
                          '');
                    } else if (lowerText.contains('medium priority') ||
                        lowerText.contains('priority medium')) {
                      newPriority = 'Medium';
                      title = title.replaceAll(
                          RegExp(r'\b(medium priority|priority medium)\b',
                              caseSensitive: false),
                          '');
                    } else if (lowerText.contains('low priority') ||
                        lowerText.contains('priority low')) {
                      newPriority = 'Low';
                      title = title.replaceAll(
                          RegExp(r'\b(low priority|priority low)\b',
                              caseSensitive: false),
                          '');
                    }

                    // Date parsing
                    if (lowerText.contains('tomorrow')) {
                      newDate = DateTime.now().add(const Duration(days: 1));
                      title = title.replaceAll(
                        RegExp(r'\btomorrow\b', caseSensitive: false),
                        '',
                      );
                    } else if (lowerText.contains('today')) {
                      newDate = DateTime.now();
                      title = title.replaceAll(
                        RegExp(r'\btoday\b', caseSensitive: false),
                        '',
                      );
                    } else if (lowerText.contains('next week')) {
                      newDate = DateTime.now().add(const Duration(days: 7));
                      title = title.replaceAll(
                        RegExp(r'\bnext week\b', caseSensitive: false),
                        '',
                      );
                    } else {
                      // Day of week parsing
                      final daysOfWeek = {
                        'monday': DateTime.monday,
                        'tuesday': DateTime.tuesday,
                        'wednesday': DateTime.wednesday,
                        'thursday': DateTime.thursday,
                        'friday': DateTime.friday,
                        'saturday': DateTime.saturday,
                        'sunday': DateTime.sunday,
                      };

                      for (final entry in daysOfWeek.entries) {
                        if (lowerText.contains(entry.key)) {
                          final now = DateTime.now();
                          int daysUntil = entry.value - now.weekday;
                          if (daysUntil <= 0) daysUntil += 7;
                          newDate = now.add(Duration(days: daysUntil));

                          // Try to remove "on [day]" first
                          title = title.replaceAll(
                            RegExp(r'\bon\s+' + entry.key + r'\b',
                                caseSensitive: false),
                            '',
                          );
                          // Then remove just "[day]"
                          title = title.replaceAll(
                            RegExp(r'\b' + entry.key + r'\b',
                                caseSensitive: false),
                            '',
                          );
                          break;
                        }
                      }
                    }

                    // Time parsing (e.g., "at 5 pm", "at 10:30")
                    final timeRegex = RegExp(
                      r'at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?',
                      caseSensitive: false,
                    );
                    final timeMatch = timeRegex.firstMatch(lowerText);

                    if (timeMatch != null) {
                      int hour = int.parse(timeMatch.group(1)!);
                      final minute = int.parse(timeMatch.group(2) ?? '0');
                      final period = timeMatch.group(3);

                      if (period == 'pm' && hour < 12) hour += 12;
                      if (period == 'am' && hour == 12) hour = 0;

                      newTime = TimeOfDay(hour: hour, minute: minute);

                      // Update date with new time
                      newDate = DateTime(
                        newDate.year,
                        newDate.month,
                        newDate.day,
                        newTime.hour,
                        newTime.minute,
                      );

                      title = title.replaceAll(timeMatch.group(0)!, '');
                    }

                    // Clean up title
                    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();

                    setState(() {
                      titleController.text = title;
                      selectedDate = newDate;
                      selectedTime = newTime;
                      selectedPriority = newPriority;
                    });
                  },
                );
              }
            } else {
              setState(() => isListening = false);
              speech.stop();
            }
          }

          return AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Text(
              task == null ? 'Add Task' : 'Edit Task',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Title',
                      labelStyle: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.electricPurple),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isListening ? Icons.mic : Icons.mic_none,
                          color: isListening
                              ? AppColors.neonGreen
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        onPressed: toggleListening,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descriptionController,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Description',
                      labelStyle: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.electricPurple),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.image),
                        color: AppColors.electricPurple,
                        onPressed: () async {
                          final ImagePicker picker = ImagePicker();
                          final XFile? image = await picker.pickImage(
                            source: ImageSource.gallery,
                          );
                          if (image != null) {
                            setState(() {
                              selectedImage = image;
                            });
                          }
                        },
                      ),
                      if (selectedImage != null)
                        Expanded(
                          child: Text(
                            selectedImage!.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Due Date & Time',
                    style: TextStyle(
                      color: AppColors.electricPurple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime.now(),
                              lastDate: DateTime(2101),
                              builder: (context, child) {
                                return Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: Theme.of(context).colorScheme
                                        .copyWith(
                                          primary: AppColors.electricPurple,
                                          onPrimary: AppColors.pureWhite,
                                        ),
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (picked != null && picked != selectedDate) {
                              setState(() {
                                selectedDate = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                  selectedTime.hour,
                                  selectedTime.minute,
                                );
                              });
                            }
                          },
                          icon: Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          label: Text(
                            "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}",
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onSurface,
                            side: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final TimeOfDay? picked = await showTimePicker(
                              context: context,
                              initialTime: selectedTime,
                              builder: (context, child) {
                                return Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: Theme.of(context).colorScheme
                                        .copyWith(
                                          primary: AppColors.electricPurple,
                                          onPrimary: AppColors.pureWhite,
                                          surface: Theme.of(
                                            context,
                                          ).colorScheme.surface,
                                          onSurface: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                    timePickerTheme: TimePickerThemeData(
                                      dayPeriodColor:
                                          WidgetStateColor.resolveWith(
                                            (states) =>
                                                states.contains(
                                                  WidgetState.selected,
                                                )
                                                ? AppColors.electricPurple
                                                : Colors.transparent,
                                          ),
                                      dayPeriodTextColor:
                                          WidgetStateColor.resolveWith(
                                            (states) =>
                                                states.contains(
                                                  WidgetState.selected,
                                                )
                                                ? AppColors.pureWhite
                                                : Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
                                          ),
                                      dialHandColor: AppColors.electricPurple,
                                      dialBackgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                    ),
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (picked != null && picked != selectedTime) {
                              setState(() {
                                selectedTime = picked;
                                selectedDate = DateTime(
                                  selectedDate.year,
                                  selectedDate.month,
                                  selectedDate.day,
                                  selectedTime.hour,
                                  selectedTime.minute,
                                );
                              });
                            }
                          },
                          icon: Icon(
                            Icons.access_time,
                            size: 16,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          label: Text(
                            selectedTime.format(context),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onSurface,
                            side: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Priority',
                    style: TextStyle(
                      color: AppColors.electricPurple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedPriority,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.electricPurple,
                        ),
                      ),
                    ),
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    items: ['High', 'Medium', 'Low'].map((String priority) {
                      return DropdownMenuItem<String>(
                        value: priority,
                        child: Text(
                          priority,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          selectedPriority = newValue;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Category',
                    style: TextStyle(
                      color: AppColors.electricPurple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.electricPurple,
                        ),
                      ),
                    ),
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    items: ['General', 'Work', 'Personal', 'Study', 'Health', 'Finance'].map((String category) {
                      return DropdownMenuItem<String>(
                        value: category,
                        child: Text(
                          category,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          selectedCategory = newValue;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  if (titleController.text.isNotEmpty) {
                    // Check for duplicate date/time
                    final isDuplicate = _tasks.any((t) {
                      if (task != null && t.id == task.id) return false;
                      return t.dueDate.year == selectedDate.year &&
                          t.dueDate.month == selectedDate.month &&
                          t.dueDate.day == selectedDate.day &&
                          t.dueDate.hour == selectedDate.hour &&
                          t.dueDate.minute == selectedDate.minute;
                    });

                    if (isDuplicate) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('A task already exists at this time!'),
                          backgroundColor: AppColors.cyberRed,
                        ),
                      );
                      return;
                    }

                    if (task == null) {
                      _addTask(
                        titleController.text,
                        descriptionController.text,
                        selectedDate,
                        selectedImage,
                        null,
                        selectedPriority,
                        selectedCategory,
                      );
                    } else {
                      _editTask(
                        task,
                        titleController.text,
                        descriptionController.text,
                        selectedDate,
                        selectedPriority,
                        null,
                        selectedCategory,
                      );
                    }
                    Navigator.pop(context);
                  }
                },
                child: const Text(
                  'Save',
                  style: TextStyle(color: AppColors.electricPurple),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      HomeScreen(
        tasks: _tasks.where((t) => !t.isCompleted).toList(),
        onTaskToggle: _toggleTaskCompletion,
        onTaskDelete: _deleteTask,
        onTaskEdit: (task) => _showAddEditTaskDialog(task: task),
        xp: _xp,
        level: _level,
      ),
      HomeScreen(
        tasks: _tasks.where((t) => t.isCompleted).toList(),
        onTaskToggle: _toggleTaskCompletion,
        onTaskDelete: _deleteTask,
        onTaskEdit: (task) => _showAddEditTaskDialog(task: task),
        xp: _xp,
        level: _level,
      ),
      const SizedBox.shrink(), // Placeholder for +
      const DashboardScreen(), // Charts
      const SettingsScreen(),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        selectedItemColor: AppColors.electricPurple,
        unselectedItemColor: Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.6),
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        onTap: (index) {
          if (index == 2) {
            _showAddEditTaskDialog();
          } else {
            _onItemTapped(index);
          }
        },
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.check_circle_outline),
            activeIcon: Icon(Icons.check_circle),
            label: 'Completed',
          ),
          BottomNavigationBarItem(
            icon: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: AppColors.electricPurple,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.lilacGlow,
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(
                Icons.add,
                color: AppColors.pureWhite,
                size: 28,
              ),
            ),
            label: '',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
