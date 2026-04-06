import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/task_item.dart';
import '../services/local_store.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _store = LocalStore();
  final _controller = TextEditingController();
  bool _dirty = false;
  bool _extracting = false;
  String? _lastExtractionSource;

  static const String _prodBaseUrl = 'https://web-production-e7381.up.railway.app';

  @override
  void initState() {
    super.initState();
    _controller.text = _store.getNotesDraft();
    _controller.addListener(() {
      if (!_dirty) {
        setState(() => _dirty = true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> _extractTasks(String raw) {
    final lines = raw.split(RegExp(r'\r?\n'));
    final out = <String>[];

    for (final l in lines) {
      final line = l.trimRight();
      if (line.trim().isEmpty) continue;

      final trimmed = line.trimLeft();

      final isHeading = trimmed.startsWith('#') || trimmed.endsWith(':');
      if (isHeading) continue;

      final checkboxMatch = RegExp(r'^(?:[-*]\s*)?\[\s*[xX ]\s*\]\s+(.+)$').firstMatch(trimmed);
      if (checkboxMatch != null) {
        final t = checkboxMatch.group(1)?.trim();
        if (t != null && t.isNotEmpty) out.add(t);
        continue;
      }

      final bulletMatch = RegExp(r'^(?:[-*•]\s+)(.+)$').firstMatch(trimmed);
      if (bulletMatch != null) {
        final t = bulletMatch.group(1)?.trim();
        if (t != null && t.isNotEmpty) out.add(t);
        continue;
      }

      final numberedMatch = RegExp(r'^\d+\.(?:\s+)(.+)$').firstMatch(trimmed);
      if (numberedMatch != null) {
        final t = numberedMatch.group(1)?.trim();
        if (t != null && t.isNotEmpty) out.add(t);
        continue;
      }
    }

    final seen = <String>{};
    final unique = <String>[];
    for (final t in out) {
      final k = t.toLowerCase();
      if (seen.contains(k)) continue;
      seen.add(k);
      unique.add(t);
    }

    return unique;
  }

  Future<void> _save() async {
    await _store.setNotesDraft(_controller.text);
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved')),
    );
  }

  Future<void> _extractAndAddTasks() async {
    if (_extracting) return;
    setState(() => _extracting = true);

    final raw = _controller.text;
    List<String> tasks = [];
    var usedAi = false;
    String? failReason;

    if (raw.trim().isEmpty) {
      setState(() {
        _extracting = false;
        _lastExtractionSource = 'Failed';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write a note first')),
      );
      return;
    }

    final baseUrl = _store.getUseProd() ? _prodBaseUrl : _store.getApiBaseUrl();
    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/v1/extract_tasks'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'text': raw}),
          )
          .timeout(const Duration(seconds: 55));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final list = data['tasks'];
        if (list is List) {
          tasks = list
              .map((e) => (e is String) ? e.trim() : '')
              .where((e) => e.isNotEmpty)
              .toList(growable: false);
          usedAi = tasks.isNotEmpty;
        }
        if (!usedAi) {
          failReason = 'AI returned no tasks';
        }
      } else {
        try {
          final data = jsonDecode(resp.body);
          final err = (data is Map && data['error'] is String)
              ? data['error'] as String
              : 'server_error';
          final msg = (data is Map && data['message'] is String)
              ? (data['message'] as String).trim()
              : '';
          if (err == 'rate_limited') {
            failReason = 'AI is rate-limited. Try again in a minute.';
          } else if (err == 'timeout') {
            failReason = 'AI timed out. Try again.';
          } else {
            failReason =
                'AI extraction failed (${resp.statusCode}). ${msg.isNotEmpty ? msg : err} ($baseUrl/v1/extract_tasks)';
          }
        } catch (_) {
          final rawBody = resp.body.trim();
          final snippet = rawBody.isEmpty
              ? ''
              : (rawBody.length > 180 ? rawBody.substring(0, 180) : rawBody);
          failReason = snippet.isEmpty
              ? 'AI extraction failed (${resp.statusCode}). ($baseUrl/v1/extract_tasks)'
              : 'AI extraction failed (${resp.statusCode}). $snippet ($baseUrl/v1/extract_tasks)';
        }
      }
    } catch (e) {
      failReason =
          'Could not reach AI server. ($baseUrl/v1/extract_tasks)\n${e.toString()}';
    }

    if (!mounted) return;
    setState(() {
      _lastExtractionSource = usedAi ? 'AI' : 'Failed';
    });

    if (tasks.isEmpty) {
      setState(() => _extracting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failReason ?? 'AI extraction failed',
          ),
        ),
      );
      return;
    }

    var order = _store.nextTaskOrder();
    for (final t in tasks) {
      final task = TaskItem(
        id: DateTime.now().microsecondsSinceEpoch.toString() + order.toString(),
        createdAt: DateTime.now(),
        text: t,
        order: order,
      );
      await _store.addTask(task);
      order += 1;
    }

    if (!mounted) return;
    setState(() => _extracting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Added ${tasks.length} tasks (AI)',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notes'),
          actions: [
            TextButton(
              onPressed: _dirty ? _save : null,
              child: const Text('Save'),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_lastExtractionSource != null) ...[
                Row(
                  children: [
                    Icon(
                      _lastExtractionSource == 'AI'
                          ? Icons.auto_awesome
                          : Icons.error_outline,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Last extraction: $_lastExtractionSource',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: 'Write self-talk, plans, checklists…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _extracting ? null : _extractAndAddTasks,
                  child: _extracting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Extract tasks to Tasks'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
