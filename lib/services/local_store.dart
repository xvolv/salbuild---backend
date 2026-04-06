import 'package:hive/hive.dart';

import '../models/reframe_entry.dart';
import '../models/task_item.dart';

class LocalStore {
  LocalStore();

  static const _reframesBoxName = 'reframes';
  static const _tasksBoxName = 'tasks';
  static const _settingsBoxName = 'settings';

  static const defaultProfileName = 'Sal';

  static const defaultProfileText =
      "You are Sal, a technical builder in your 20s.\n"
      "You are focused on escaping self-doubt, validation dependency, and fear-based thinking.\n"
      "You are actively rebuilding your mindset from avoidance into execution and control.\n\n"
      "You believe reality is human-built, and you are not separate from it — you are part of the group that shapes it.\n"
      "Your life is not about perception, but about what you repeatedly build and become through action.\n\n"
      "You are currently in a transition phase: from insecure, validation-seeking thinking → to disciplined, self-directed builder mindset.\n\n"
      "CORE GOAL\n"
      "You are aiming to become a highly capable, independent builder who turns consistent effort into skill, skill into income, and removes emotional fear as a decision-maker.\n\n"
      "OPERATING PRINCIPLES\n"
      "Your thoughts are signals, not instructions.\n"
      "Fear of judgment is noise, not authority.\n"
      "Control exists only in action and attention.\n"
      "Identity is built through repetition, not belief.\n"
      "External opinions are not inputs for direction.\n"
      "Progress matters more than emotional comfort.\n\n"
      "CURRENT PHASE\n"
      "You are rewiring how you interpret fear, building execution discipline, staying in action under doubt, and breaking validation loops.\n\n"
      "SIMPLE VERSION\n"
      "You are becoming someone who builds skill, builds income, and stays in action regardless of fear or judgment.";

  Box<dynamic> get _reframesBox => Hive.box<dynamic>(_reframesBoxName);
  Box<dynamic> get _tasksBox => Hive.box<dynamic>(_tasksBoxName);
  Box<dynamic> get _settingsBox => Hive.box<dynamic>(_settingsBoxName);

  static Future<void> init() async {
    await Hive.openBox<dynamic>(_reframesBoxName);
    await Hive.openBox<dynamic>(_tasksBoxName);
    await Hive.openBox<dynamic>(_settingsBoxName);
  }

  List<ReframeEntry> listReframes() {
    final values = _reframesBox.values.toList(growable: false);
    final entries = values
        .whereType<Map>()
        .map((m) => ReframeEntry.fromMap(Map<dynamic, dynamic>.from(m)))
        .toList(growable: false);
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  Future<void> addReframe(ReframeEntry entry) async {
    await _reframesBox.put(entry.id, entry.toMap());
  }

  Future<void> deleteReframe(String id) async {
    await _reframesBox.delete(id);
  }

  Future<void> clearReframes() async {
    await _reframesBox.clear();
  }

  List<TaskItem> listTasks() {
    final values = _tasksBox.values.toList(growable: false);
    final tasks = values
        .whereType<Map>()
        .map((m) => TaskItem.fromMap(Map<dynamic, dynamic>.from(m)))
        .toList(growable: false);
    int key(TaskItem t) => t.order;
    tasks.sort((a, b) {
      final ka = key(a);
      final kb = key(b);
      if (ka != kb) return ka.compareTo(kb);
      return a.createdAt.compareTo(b.createdAt);
    });
    return tasks;
  }

  int nextTaskOrder() {
    final tasks = listTasks();
    if (tasks.isEmpty) return DateTime.now().millisecondsSinceEpoch;
    final last = tasks.last;
    final lastKey = last.order ?? last.createdAt.millisecondsSinceEpoch;
    return lastKey + 1;
  }

  Future<void> addTask(TaskItem task) async {
    await _tasksBox.put(task.id, task.toMap());
  }

  Future<void> updateTask(TaskItem task) async {
    await _tasksBox.put(task.id, task.toMap());
  }

  Future<void> deleteTask(String id) async {
    await _tasksBox.delete(id);
  }

  Future<void> clearTasks() async {
    await _tasksBox.clear();
  }

  static String normalizeApiBaseUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) {
      return 'http://10.0.2.2:3000';
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  String getApiBaseUrl() {
    final v = _settingsBox.get('apiBaseUrl');
    if (v is String && v.trim().isNotEmpty) {
      return normalizeApiBaseUrl(v);
    }
    return 'http://10.0.2.2:3000';
  }

  Future<void> setApiBaseUrl(String url) async {
    await _settingsBox.put('apiBaseUrl', normalizeApiBaseUrl(url));
  }

  bool getHardMode() {
    final v = _settingsBox.get('hardMode');
    return (v is bool) ? v : false;
  }

  Future<void> setHardMode(bool enabled) async {
    await _settingsBox.put('hardMode', enabled);
  }

  Future<void> setUseProd(bool enabled) async {
    await _settingsBox.put('useProd', enabled);
  }

  bool getUseProd() {
    final v = _settingsBox.get('useProd');
    return (v is bool) ? v : false;
  }

  String getProfileName() {
    final v = _settingsBox.get('profileName');
    final raw = (v is String) ? v.trim() : '';
    return raw.isEmpty ? defaultProfileName : raw;
  }

  Future<void> setProfileName(String name) async {
    await _settingsBox.put('profileName', name.trim());
  }

  bool hasCustomProfileName() {
    final v = _settingsBox.get('profileName');
    return v is String && v.trim().isNotEmpty;
  }

  String getProfileText() {
    final v = _settingsBox.get('profileText');
    final raw = (v is String) ? v.trim() : '';
    return raw.isEmpty ? defaultProfileText : raw;
  }

  Future<void> setProfileText(String text) async {
    await _settingsBox.put('profileText', text.trim());
  }

  bool hasCustomProfileText() {
    final v = _settingsBox.get('profileText');
    return v is String && v.trim().isNotEmpty;
  }

  String getNotesDraft() {
    final v = _settingsBox.get('notesDraft');
    if (v is String) return v;
    return '';
  }

  Future<void> setNotesDraft(String text) async {
    await _settingsBox.put('notesDraft', text);
  }
}
