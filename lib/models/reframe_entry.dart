class ReframeEntry {
  ReframeEntry({
    required this.id,
    required this.createdAt,
    required this.input,
    required this.hardMode,
    required this.lines,
  });

  final String id;
  final DateTime createdAt;
  final String input;
  final bool hardMode;
  final List<String> lines;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'input': input,
      'hardMode': hardMode,
      'lines': lines,
    };
  }

  static ReframeEntry fromMap(Map<dynamic, dynamic> map) {
    return ReframeEntry(
      id: map['id'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      input: map['input'] as String,
      hardMode: (map['hardMode'] as bool?) ?? false,
      lines: (map['lines'] as List).map((e) => e.toString()).toList(),
    );
  }
}
