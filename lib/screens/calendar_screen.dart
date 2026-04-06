import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/task_item.dart';
import '../services/local_store.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _store = LocalStore();
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<TaskItem> _tasks = [];
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    _tasks = _store.listTasks();
  }

  DateTime _dayKey(DateTime day) => DateTime(day.year, day.month, day.day);

  bool _hasTaskOn(DateTime day) {
    if (_tasks.isEmpty) return false;
    final key = _dayKey(day);
    return _tasks.any((t) {
      final d = t.scheduledFor;
      if (d == null) return false;
      return _dayKey(d) == key;
    });
  }

  List<TaskItem> _tasksForDay(DateTime day) {
    final key = _dayKey(day);
    return _tasks.where((t) {
      final d = t.scheduledFor;
      return d != null && _dayKey(d) == key;
    }).toList();
  }

  bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  bool _isPastDay(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(day.year, day.month, day.day);
    return d.isBefore(today);
  }

  void _refreshTasks() {
    if (!mounted) return;
    setState(() {
      _tasks = _store.listTasks();
    });
  }

  Future<void> _handleDaySelection(DateTime day) async {
    if (!mounted || _sheetOpen) return;
    _sheetOpen = true;

    try {
      final items = _tasksForDay(day);

      // If there's exactly one task, open the edit sheet directly.
      if (items.length == 1) {
        await _showEditTaskSheet(day, items.first);
      }
      // If there are multiple tasks, show a list first.
      else if (items.length > 1) {
        await _showTasksListSheet(day);
      }
      // If no tasks, open the add sheet.
      else {
        await _showEditTaskSheet(day, null);
      }
    } finally {
      _sheetOpen = false;
      _refreshTasks();
    }
  }

  Future<void> _showEditTaskSheet(DateTime day, TaskItem? existingTask) async {
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _TaskEditorSheet(day: day, task: existingTask),
    );

    if (!mounted || result == null) return;

    if (result == 'DELETE') {
      if (existingTask != null) {
        await _store.deleteTask(existingTask.id);
      }
    } else if (result is String) {
      final trimmed = result.trim();
      if (trimmed.isEmpty) {
        if (existingTask != null) {
          await _store.deleteTask(existingTask.id);
        }
      } else {
        final task = existingTask != null
            ? TaskItem(
                id: existingTask.id,
                createdAt: existingTask.createdAt,
                text: trimmed,
                order: existingTask.order,
                scheduledFor: existingTask.scheduledFor,
              )
            : TaskItem(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                createdAt: DateTime.now(),
                text: trimmed,
                order: _store.nextTaskOrder(),
                scheduledFor: _dayKey(day),
              );
        await _store.addTask(task);
      }
    }
  }

  Future<void> _showTasksListSheet(DateTime day) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final items = _tasksForDay(day);
            final dateLabel = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Tasks for $dateLabel', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('No tasks remaining.'),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final t = items[index];
                            return ListTile(
                              title: Text(t.text),
                              trailing: const Icon(Icons.edit),
                              onTap: () async {
                                await _showEditTaskSheet(day, t);
                                setModalState(() {});
                                _refreshTasks();
                              },
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () async {
                        await _showEditTaskSheet(day, null);
                        setModalState(() {});
                        _refreshTasks();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add Another Task'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _tagMarker(BuildContext context) {
    return Positioned(
      right: 4,
      bottom: 4,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.zero,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(title: const Text('Month')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: TableCalendar(
            firstDay: DateTime.utc(2000, 1, 1),
            lastDay: DateTime.utc(2100, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
            onDaySelected: (selected, focused) {
              if (!mounted) return;
              setState(() {
                _selectedDay = selected;
                _focusedDay = focused;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _handleDaySelection(selected);
              });
            },
            onPageChanged: (d) {
              if (!mounted) return;
              setState(() => _focusedDay = d);
            },
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              todayDecoration: const BoxDecoration(
                shape: BoxShape.rectangle,
              ),
              defaultTextStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
              ),
              weekendTextStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            calendarBuilders: CalendarBuilders(
              todayBuilder: (context, day, focusedDay) {
                final hasTask = _hasTaskOn(day);
                return Container(
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (hasTask) _tagMarker(context),
                    ],
                  ),
                );
              },
              defaultBuilder: (context, day, focusedDay) {
                final isPast = _isPastDay(day);
                final isToday = _isToday(day);
                final hasTask = _hasTaskOn(day);

                if (isToday) {
                  return Container(
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (hasTask) _tagMarker(context),
                      ],
                    ),
                  );
                }

                final child = Center(
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      color: isPast
                          ? Theme.of(context).colorScheme.onSurface.withOpacity(0.45)
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                );

                if (!isPast) {
                  if (!hasTask) return child;
                  return Stack(
                    children: [
                      Positioned.fill(child: child),
                      _tagMarker(context),
                    ],
                  );
                }

                return Container(
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(child: child),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Center(
                            child: Icon(
                              Icons.close,
                              size: 26,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ),
                      ),
                      if (hasTask) _tagMarker(context),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskEditorSheet extends StatefulWidget {
  final DateTime day;
  final TaskItem? task;

  const _TaskEditorSheet({required this.day, this.task});

  @override
  State<_TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<_TaskEditorSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task?.text ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = '${widget.day.year}-${widget.day.month.toString().padLeft(2, '0')}-${widget.day.day.toString().padLeft(2, '0')}';
    final isEditing = widget.task != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isEditing ? 'Edit Task ($dateLabel)' : 'Add Task ($dateLabel)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (isEditing)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => Navigator.of(context).pop('DELETE'),
                      tooltip: 'Delete Task',
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'What needs to be done?',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (v) => Navigator.of(context).pop(v),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_controller.text),
                      child: Text(isEditing ? 'Update' : 'Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
