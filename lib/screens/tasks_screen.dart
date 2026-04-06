import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'dart:async';
import 'dart:ui';

import '../models/task_item.dart';
import '../services/local_store.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final _store = LocalStore();
  final _controller = TextEditingController();

  final _speech = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _transcription = '';
  String _bestTranscription = '';
  bool _sheetOpen = false;
  void Function(void Function())? _sheetSetState;

  late List<TaskItem> _tasks;

  final Set<String> _pendingDeleteIds = <String>{};
  String? _draggingTaskId;
  String? _quranQuote;
  bool _quoteLoading = false;

  @override
  void initState() {
    super.initState();
    _tasks = _store.listTasks();
    _initSpeech();
    _fetchApiQuote();
  }

  @override
  void dispose() {
    _controller.dispose();
    _speech.stop();
    super.dispose();
  }

  // Local Quran quotes for offline fallback with Arabic
  static const List<Map<String, String>> _localQuranQuotes = [
    {
      'text': 'Indeed, Allah will not change the condition of a people until they change what is in themselves.',
      'arabic': 'إِنَّ اللَّهَ لَا يُغَيِّرُ مَا بِقَوْمٍ حَتَّىٰ يُغَيِّرُوا مَا بِأَنفُسِهِمْ',
      'reference': 'Quran 13:11',
      'surah': '13',
      'ayah': '11',
    },
    {
      'text': 'And whoever fears Allah, He will make for him a way out and provide for him from where he does not expect.',
      'arabic': 'وَمَن يَتَّقِ اللَّهَ يَجْعَل لَّهُ مَخْرَجًا وَيَرْزُقْهُ مِنْ حَيْثُ لَا يَحْتَسِبُ',
      'reference': 'Quran 65:2-3',
      'surah': '65',
      'ayah': '2',
    },
    {
      'text': 'So indeed, with hardship comes ease. Indeed, with hardship comes ease.',
      'arabic': 'فَإِنَّ مَعَ الْعُسْرِ يُسْرًا إِنَّ مَعَ الْعُسْرِ يُسْرًا',
      'reference': 'Quran 94:5-6',
      'surah': '94',
      'ayah': '5',
    },
    {
      'text': 'And whoever relies upon Allah, then He is sufficient for him.',
      'arabic': 'وَمَن يَتَوَكَّلْ عَلَى اللَّهِ فَهُوَ حَسْبُهُ',
      'reference': 'Quran 65:3',
      'surah': '65',
      'ayah': '3',
    },
    {
      'text': 'And do not throw yourselves into destruction.',
      'arabic': 'وَلَا تُلْقُوا بِأَيْدِيكُمْ إِلَى التَّهْلُكَةِ',
      'reference': 'Quran 2:195',
      'surah': '2',
      'ayah': '195',
    },
    {
      'text': 'Indeed, Allah is with the patient.',
      'arabic': 'إِنَّ اللَّهَ مَعَ الصَّابِرِينَ',
      'reference': 'Quran 2:153',
      'surah': '2',
      'ayah': '153',
    },
    {
      'text': 'And whoever strives only strives for himself.',
      'arabic': 'وَمَن جَاهَدَ فَإِنَّمَا يُجَاهِدُ لِنَفْسِهِ',
      'reference': 'Quran 17:7',
      'surah': '17',
      'ayah': '7',
    },
    {
      'text': 'And say, "My Lord, increase me in knowledge."',
      'arabic': 'وَقُل رَّبِّ زِدْنِي عِلْمًا',
      'reference': 'Quran 20:114',
      'surah': '20',
      'ayah': '114',
    },
    {
      'text': 'Indeed, with difficulty comes ease.',
      'arabic': 'إِنَّ مَعَ الْعُسْرِ يُسْرًا',
      'reference': 'Quran 94:5',
      'surah': '94',
      'ayah': '5',
    },
  ];

  Future<void> _fetchApiQuote() async {
    if (_quoteLoading) return; // Prevent duplicate requests
    
    setState(() => _quoteLoading = true);
    
    try {
      await _fetchQuranQuote();
    } finally {
      setState(() => _quoteLoading = false);
    }
  }

  Future<void> _fetchQuranQuote() async {
    try {
      // Try multiple Quran API endpoints for reliability
      final endpoints = [
        'https://api.alquran.cloud/v1/ayah/${_getRandomAyah()}/en.asad',
        'https://api.alquran.cloud/v1/ayah/${_getRandomAyah()}/editions/en.asad,ar.alafasy',
      ];
      
      for (final endpoint in endpoints) {
        try {
          final response = await http.get(
            Uri.parse(endpoint),
          ).timeout(const Duration(seconds: 3)); // Fast timeout
          
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            
            if (endpoint.contains('editions')) {
              // Get both English and Arabic
              final editions = data['data'] as List;
              String? englishText, arabicText, surahName;
              int? ayahNumber, surahNumber;
              
              for (final edition in editions) {
                if (edition['edition']['language'] == 'en') {
                  englishText = edition['text'];
                  surahName = edition['surah']['englishName'];
                  ayahNumber = edition['numberInSurah'];
                  surahNumber = edition['surah']['number'];
                } else if (edition['edition']['language'] == 'ar') {
                  arabicText = edition['text'];
                }
              }
              
              if (englishText != null && arabicText != null && surahName != null && ayahNumber != null) {
                setState(() {
                  _quranQuote = '"$englishText"\n$arabicText\n— $surahName $ayahNumber';
                });
                return;
              }
            } else {
              // Single edition fallback
              final ayah = data['data'];
              final text = ayah['text'] as String?;
              final surah = ayah['surah']['englishName'] as String?;
              final ayahNumber = ayah['numberInSurah'] as int?;
              final surahNumber = ayah['surah']['number'] as int?;
              
              if (text != null && surah != null && ayahNumber != null && surahNumber != null) {
                // Try to get Arabic text separately
                final arabicResponse = await http.get(
                  Uri.parse('https://api.alquran.cloud/v1/ayah/$surahNumber:$ayahNumber/ar.alafasy'),
                ).timeout(const Duration(seconds: 2));
                
                String? arabicText;
                if (arabicResponse.statusCode == 200) {
                  final arabicData = jsonDecode(arabicResponse.body);
                  arabicText = arabicData['data']['text'] as String?;
                }
                
                setState(() {
                  if (arabicText != null) {
                    _quranQuote = '"$text"\n$arabicText\n— $surah $ayahNumber';
                  } else {
                    _quranQuote = '"$text"\n— $surah $ayahNumber';
                  }
                });
                return;
              }
            }
          }
        } catch (e) {
          continue; // Try next endpoint
        }
      }
      
      // Fallback to local Quran quotes
      _useLocalQuranQuote();
      
    } catch (e) {
      _useLocalQuranQuote();
    }
  }

  void _useLocalQuranQuote() {
    final randomQuote = _localQuranQuotes[
      DateTime.now().millisecond % _localQuranQuotes.length
    ];
    setState(() {
      if (randomQuote['arabic'] != null && randomQuote['arabic']!.isNotEmpty) {
        _quranQuote = '"${randomQuote['text']}"\n${randomQuote['arabic']}\n— ${randomQuote['reference']}';
      } else {
        _quranQuote = '"${randomQuote['text']}"\n— ${randomQuote['reference']}';
      }
    });
  }

  Future<void> _copyAllTasks() async {
    if (_tasks.isEmpty) return;

    final lines = <String>[];
    for (final t in _tasks) {
      final text = t.text.trim();
      if (text.isEmpty) continue;

      if (t.duration != null && t.durationUnit != null) {
        lines.add('- $text (${t.duration} ${t.durationUnit})');
      } else {
        lines.add('- $text');
      }
    }

    final payload = lines.join('\n');
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${lines.length} tasks')),
    );
  }

  int _getRandomAyah() {
    // Commonly beneficial ayahs (1-6236 total ayahs in Quran)
    final beneficialAyahs = [
      2, 45, 46, 153, 155, 157, 158, 286, // Al-Baqarah
      3, 102, 103, 104, 133, 134, 200, // Aal-e-Imran
      13, 11, 20, 21, 22, // Ar-Ra'd
      16, 97, 128, // An-Nahl
      17, 7, 19, 80, 81, // Al-Isra
      20, 114, // Ta-Ha
      23, 115, 116, // Al-Mu'minun
      24, 35, 36, 37, 38, 39, 40, 41, // An-Nur
      28, 77, // Al-Qasas
      29, 69, // Al-Ankabut
      30, 30, // Ar-Rum
      31, 12, 13, 14, 15, 16, 17, 18, // Luqman
      33, 35, 41, 70, 71, // Al-Ahzab
      35, 29, 30, // Fatir
      39, 9, 10, 53, // Az-Zumar
      40, 39, 40, 41, 42, 43, 44, // Ghafir
      42, 30, 36, 37, // Ash-Shura
      57, 21, 23, // Al-Hadid
      59, 9, 18, 19, // Al-Hashr
      62, 9, 10, // Al-Jumu'ah
      64, 13, 14, 16, 17, 18, // At-Taghabun
      65, 2, 3, 7, // At-Talaq
      67, 2, 12, 13, 15, // Al-Mulk
      94, 5, 6, // Ash-Sharh
      103, 1, 2, 3, // Al-Asr
    ];
    return beneficialAyahs[DateTime.now().millisecond % beneficialAyahs.length];
  }

  void _armDelete(String id) {
    setState(() => _pendingDeleteIds.add(id));
  }

  void _cancelDelete() {
    if (_pendingDeleteIds.isEmpty) return;
    setState(() => _pendingDeleteIds.clear());
  }

  void _startDrag(String id) {
    setState(() => _draggingTaskId = id);
  }

  void _endDrag() {
    if (!mounted) return;
    setState(() => _draggingTaskId = null);
  }

  void _showTimePickerSheet(TaskItem task) {
    int amount = task.duration ?? 1;
    String unit = task.durationUnit ?? 'min';
    final controller = TextEditingController(text: amount.toString());
    final focusNode = FocusNode();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Set time to complete',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    focusNode: focusNode,
                    controller: controller,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      amount = int.tryParse(value) ?? amount;
                    },
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 's', label: Text('sec')),
                      ButtonSegment(value: 'min', label: Text('min')),
                      ButtonSegment(value: 'h', label: Text('hour')),
                    ],
                    selected: {unit},
                    onSelectionChanged: (newSelection) {
                      unit = newSelection.first;
                      setModalState(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () {
                          final updated = task.copyWith(
                            duration: amount,
                            durationUnit: unit,
                          );
                          _store.updateTask(updated);
                          setState(() => _tasks = _store.listTasks());
                          Navigator.pop(context);
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      controller.dispose();
      focusNode.dispose();
    });
  }

  Future<void> _initSpeech() async {
    final micStatus = await Permission.microphone.request();
    if (micStatus != PermissionStatus.granted) {
      return;
    }

    final available = await _speech.initialize(
      onError: (e) => setState(() => _speechEnabled = false),
      onStatus: (s) {
        final isListeningNow = s.toLowerCase() == 'listening';
        if (!mounted) return;
        if (!_sheetOpen) return;
        setState(() => _isListening = isListeningNow);
        _sheetSetState?.call(() {});
      },
    );

    if (!mounted) return;
    setState(() => _speechEnabled = available);
  }

  Future<void> _startListening() async {
    if (!_speechEnabled) return;
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        if (!_sheetOpen) return;
        final text = result.recognizedWords;
        setState(() {
          _transcription = text;
          if (text.trim().length > _bestTranscription.trim().length) {
            _bestTranscription = text;
          }
        });
        _sheetSetState?.call(() {});
      },
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 4),
      partialResults: true,
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
  }

  String _finalTranscript() {
    final best = _bestTranscription.trim();
    if (best.isNotEmpty) return best;
    return _transcription.trim();
  }

  Future<void> _openSpeechSheet() async {
    if (!_speechEnabled) {
      await _initSpeech();
      if (!_speechEnabled) return;
    }

    if (!mounted) return;

    final editController = TextEditingController();
    var userEdited = false;

    _sheetOpen = true;
    setState(() {
      _transcription = '';
      _bestTranscription = '';
      _isListening = false;
    });

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              _sheetSetState = setModalState;

            Future<void> start() async {
              setModalState(() {
                _transcription = '';
                _bestTranscription = '';
                userEdited = false;
                editController.text = '';
              });
              await _startListening();
            }

            Future<void> stop() async {
              await _stopListening();
              setModalState(() {});
            }

            Future<void> recordAgain() async {
              await _stopListening();
              setModalState(() {
                _transcription = '';
                _bestTranscription = '';
                userEdited = false;
                editController.text = '';
              });
              await _startListening();
            }

            void close() {
              Navigator.of(context).pop();
            }

            void addAndClose() {
              final text = editController.text.trim();
              if (text.isEmpty) return;
              _controller.text = text;
              _addTask();
              Navigator.of(context).pop();
            }

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_isListening && _finalTranscript().isEmpty) {
                start();
              }
            });

            final transcript = _finalTranscript();
            if (!userEdited) {
              final next = transcript;
              if (next != editController.text) {
                editController.text = next;
                editController.selection = TextSelection.collapsed(
                  offset: editController.text.length,
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isListening ? 'Listening…' : 'Speech to text',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: close,
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: editController,
                        minLines: 3,
                        maxLines: 6,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText:
                              _isListening ? 'Say something…' : 'Tap record to start',
                        ),
                        onChanged: (_) {
                          userEdited = true;
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isListening ? stop : start,
                          icon: Icon(_isListening ? Icons.stop : Icons.mic),
                          label: Text(_isListening ? 'Stop' : 'Record'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: recordAgain,
                          child: const Text('Record again'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: editController.text.trim().isEmpty
                        ? null
                        : addAndClose,
                    child: const Text('Add task'),
                  ),
                ],
              ),
            );
            },
          );
        },
      );
    } finally {
      _sheetSetState = null;
      _sheetOpen = false;
      await _stopListening();
      editController.dispose();
    }

    if (!mounted) return;
    setState(() => _isListening = false);
  }

  Future<void> _onMicPressed() async {
    await _openSpeechSheet();
  }

  Future<void> _addTask() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final task = TaskItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      text: text,
      order: _store.nextTaskOrder(),
    );

    await _store.addTask(task);
    setState(() {
      _controller.clear();
      _tasks = _store.listTasks();
    });
  }

  Future<void> _persistOrder() async {
    for (var i = 0; i < _tasks.length; i++) {
      final t = _tasks[i];
      final updated = TaskItem(
        id: t.id,
        createdAt: t.createdAt,
        text: t.text,
        order: i,
        scheduledFor: t.scheduledFor,
      );
      await _store.addTask(updated);
    }
  }

  Future<void> _deleteTask(String id) async {
    await _store.deleteTask(id);
    setState(() {
      _tasks = _store.listTasks();
      _pendingDeleteIds.remove(id);
    });
  }

  Future<void> _confirmDeleteAll() async {
    if (_tasks.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete all tasks?'),
          content: const Text('This will permanently delete all tasks.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete all'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;
    await _store.clearTasks();
    if (!mounted) return;
    setState(() {
      _pendingDeleteIds.clear();
      _draggingTaskId = null;
      _tasks = _store.listTasks();
    });
  }

  String _getMotivationalQuote(String totalText) {
    final quote = _quranQuote ?? '"…"\n— Quran';
    return "$totalText of focused work. $quote";
  }

  Future<void> _openQuoteOverlay(String quote) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Quran',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        quote,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _quoteLoading
                            ? null
                            : () async {
                                await _fetchApiQuote();
                              },
                        icon: _quoteLoading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh, size: 16),
                        label: const Text('New quote'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalMinutes = _tasks.fold<int>(0, (sum, task) {
      if (task.duration == null || task.durationUnit == null) return sum;
      final duration = task.duration!;
      switch (task.durationUnit) {
        case 's':
          return sum + (duration / 60).round();
        case 'min':
          return sum + duration;
        case 'h':
          return sum + (duration * 60);
        default:
          return sum;
      }
    });
    
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    String totalText;
    if (hours > 0 && minutes > 0) {
      totalText = '$hours hour${hours == 1 ? '' : 's'} $minutes min';
    } else if (hours > 0) {
      totalText = '$hours hour${hours == 1 ? '' : 's'}';
    } else {
      totalText = '$minutes min';
    }

    final motivationalQuote = _getMotivationalQuote(totalText);

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tasks'),
          actions: [
            IconButton(
              onPressed: _tasks.isEmpty ? null : _copyAllTasks,
              icon: const Icon(Icons.copy_all),
              tooltip: 'Copy all',
            ),
            IconButton(
              onPressed: _tasks.isEmpty ? null : _confirmDeleteAll,
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Delete all',
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'gotta kill --',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _addTask(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    onPressed: _onMicPressed,
                    icon: Icon(_isListening ? Icons.stop : Icons.mic),
                    tooltip: _isListening ? 'Stop recording' : 'Record',
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _addTask,
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: _tasks.length,
                  onReorderStart: (index) {
                    _cancelDelete();
                    _startDrag(_tasks[index].id);
                  },
                  onReorderEnd: (_) => _endDrag(),
                  proxyDecorator: (child, index, animation) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (BuildContext context, Widget? child) {
                        final animValue = Curves.easeInOut.transform(animation.value);
                        final elevation = lerpDouble(0, 6, animValue)!;
                        return Material(
                          elevation: elevation,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: child,
                          ),
                        );
                      },
                      child: child,
                    );
                  },
                  onReorder: (oldIndex, newIndex) {
                    if (!mounted) return;
                    final next = List<TaskItem>.from(_tasks);
                    if (newIndex > oldIndex) {
                      newIndex -= 1;
                    }
                    final item = next.removeAt(oldIndex);
                    next.insert(newIndex, item);

                    final normalized = <TaskItem>[];
                    for (var i = 0; i < next.length; i++) {
                      final t = next[i];
                      normalized.add(
                        TaskItem(
                          id: t.id,
                          createdAt: t.createdAt,
                          text: t.text,
                          order: i,
                          scheduledFor: t.scheduledFor,
                        ),
                      );
                    }

                    setState(() {
                      _cancelDelete();
                      _tasks = normalized;
                    });

                    _persistOrder();
                  },
                  itemBuilder: (context, index) {
                    final task = _tasks[index];
                    final pending = _pendingDeleteIds.contains(task.id);
                    final dragging = _draggingTaskId == task.id;
                    return Container(
                      key: ValueKey(task.id),
                      decoration: BoxDecoration(
                        color: dragging
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        border: dragging
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 3,
                              )
                            : Border(
                                bottom: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                  width: 1,
                                ),
                              ),
                        borderRadius: dragging ? BorderRadius.circular(8) : null,
                        boxShadow: dragging
                            ? [
                                BoxShadow(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: ListTile(
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.text,
                                style: pending
                                    ? TextStyle(
                                        decoration: TextDecoration.lineThrough,
                                        decorationThickness: 2,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.65),
                                      )
                                    : null,
                              ),
                            ),
                            if (task.duration != null && task.durationUnit != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  '${task.duration} ${task.durationUnit}',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: null,
                        onTap: () => _showTimePickerSheet(task),
                        trailing: IconButton(
                          icon: Icon(
                            pending ? Icons.delete_forever : Icons.delete_outline,
                            color: pending
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                          onPressed: () {
                            if (pending) {
                              _deleteTask(task.id);
                            } else {
                              _armDelete(task.id);
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (totalMinutes > 0) ...[
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _openQuoteOverlay(motivationalQuote),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            motivationalQuote,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.open_in_full,
                          size: 18,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
