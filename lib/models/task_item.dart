class TaskItem {
  final String id;
  final String text;
  final DateTime createdAt;
  final int order;
  final int? duration; 
  final String? durationUnit; 
  final DateTime? scheduledFor;

  TaskItem({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.order,
    this.duration,
    this.durationUnit,
    this.scheduledFor,
  });

  TaskItem copyWith({
    String? id,
    String? text,
    DateTime? createdAt,
    int? order,
    int? duration,
    String? durationUnit,
    DateTime? scheduledFor,
  }) {
    return TaskItem(
      id: id ?? this.id,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      order: order ?? this.order,
      duration: duration ?? this.duration,
      durationUnit: durationUnit ?? this.durationUnit,
      scheduledFor: scheduledFor ?? this.scheduledFor,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'text': text,
      if (order != null) 'order': order,
      if (duration != null) 'duration': duration,
      if (durationUnit != null) 'durationUnit': durationUnit,
      if (scheduledFor != null) 'scheduledFor': scheduledFor!.toIso8601String(),
    };
  }

  static TaskItem fromMap(Map<dynamic, dynamic> map) {
    final scheduledRaw = map['scheduledFor'];
    DateTime? scheduled;
    if (scheduledRaw is String && scheduledRaw.trim().isNotEmpty) {
      scheduled = DateTime.tryParse(scheduledRaw);
    }

    final orderRaw = map['order'];
    int order;
    if (orderRaw is int) {
      order = orderRaw;
    } else if (orderRaw is num) {
      order = orderRaw.toInt();
    } else {
      order = 0;
    }

    final durationRaw = map['duration'];
    int? duration;
    if (durationRaw is int) {
      duration = durationRaw;
    } else if (durationRaw is num) {
      duration = durationRaw.toInt();
    }

    final durationUnitRaw = map['durationUnit'];
    String? durationUnit;
    if (durationUnitRaw is String) {
      durationUnit = durationUnitRaw;
    }

    return TaskItem(
      id: map['id'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      text: map['text'] as String,
      order: order,
      duration: duration,
      durationUnit: durationUnit,
      scheduledFor: scheduled,
    );
  }
}
