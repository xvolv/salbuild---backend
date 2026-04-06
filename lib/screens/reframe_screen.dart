import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/reframe_entry.dart';
import '../services/local_store.dart';
import '../services/reframe_api.dart';

class ReframeScreen extends StatefulWidget {
  const ReframeScreen({super.key});

  @override
  State<ReframeScreen> createState() => _ReframeScreenState();
}

class _ReframeScreenState extends State<ReframeScreen> {
  final _store = LocalStore();
  final _controller = TextEditingController();

  static const String _prodBaseUrl = 'https://web-production-e7381.up.railway.app';

  bool _loading = false;
  String? _error;
  List<String>? _output;
  late bool _hardMode;
  late String _apiBaseUrl;
  late List<ReframeEntry> _history;

  @override
  void initState() {
    super.initState();
    _hardMode = _store.getHardMode();
    _apiBaseUrl = _store.getUseProd()
        ? 'https://web-production-e7381.up.railway.app'
        : _store.getApiBaseUrl();
    _history = _store.listReframes();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _friendlyError(Object e) {
    final raw = e.toString();
    if (raw.contains('rate_limited|')) {
      final parts = raw.split('rate_limited|');
      final payload = parts.length > 1 ? parts[1] : '';
      final fields = payload.split('|');
      final provider = (fields.isNotEmpty ? fields[0] : '').trim();
      final retry = (fields.length > 1 ? fields[1] : '').trim();
      final name = _store.getProfileName().trim();

      final who = name.isNotEmpty ? '$name,' : '';
      final p = provider.isNotEmpty ? provider : 'provider';
      final waitMsg = (retry.isNotEmpty && retry != 'null')
          ? ' Wait $retry seconds and try again.'
          : ' Wait a bit and try again.';
      return '$who you hit $p rate limit.$waitMsg';
    }
    return raw;
  }

  Future<void> _runReframe() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _output = null;
    });

    try {
      _apiBaseUrl = _store.getUseProd() ? _prodBaseUrl : _store.getApiBaseUrl();
      if (mounted) {
        setState(() {});
      }
      final api = ReframeApi(baseUrl: _apiBaseUrl);
      final lines = await api.reframe(
        text: text,
        hardMode: _hardMode,
        profileName: _store.getProfileName(),
        profileText: _store.getProfileText(),
      );

      final entry = ReframeEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        createdAt: DateTime.now(),
        input: text,
        hardMode: _hardMode,
        lines: lines.take(4).toList(),
      );

      await _store.addReframe(entry);

      setState(() {
        _output = entry.lines;
        _history = _store.listReframes();
      });
    } catch (e) {
      setState(() {
        _error = _friendlyError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _deleteEntry(String id) async {
    await _store.deleteReframe(id);
    setState(() {
      _history = _store.listReframes();
    });
  }

  Future<void> _clearHistory() async {
    await _store.clearReframes();
    setState(() {
      _history = _store.listReframes();
    });
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied')),
    );
  }

  Future<void> _openReflectionSheet({
    required String thought,
    required String question,
  }) async {
    if (!mounted) return;
    final apiBaseUrl = _store.getUseProd() ? _prodBaseUrl : _store.getApiBaseUrl();
    final api = ReframeApi(baseUrl: apiBaseUrl);

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
              top: 12,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: FutureBuilder<String>(
              future: api.reflect(
                text: thought,
                question: question,
                hardMode: _hardMode,
                profileName: _store.getProfileName(),
                profileText: _store.getProfileText(),
              ),
              builder: (context, snapshot) {
                final cs = Theme.of(context).colorScheme;
                final reflection = snapshot.data;
                final err = snapshot.error;

                final errText = err == null ? null : _friendlyError(err);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'THINK',
                            style: TextStyle(
                              letterSpacing: 2.2,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ),
                        ),
                        if (reflection != null && reflection.trim().isNotEmpty)
                          IconButton(
                            tooltip: 'Copy',
                            onPressed: () => _copyToClipboard(reflection),
                            icon: const Icon(Icons.content_copy),
                          ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: cs.primary.withOpacity(0.25),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      question,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                        color: cs.primary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (snapshot.connectionState != ConnectionState.done)
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _RobotLoader(size: 22),
                          SizedBox(width: 12),
                          Text('Thinking…'),
                        ],
                      )
                    else if (err != null)
                      Text(
                        err.toString(),
                        style: TextStyle(color: cs.error),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.45,
                        ),
                        child: SingleChildScrollView(
                          child: Container(
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              border: Border.all(
                                color: cs.primary.withOpacity(0.55),
                                width: 1,
                              ),
                              borderRadius: BorderRadius.zero,
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              (reflection ?? '').trim(),
                              style: TextStyle(
                                fontFamily: 'monospace',
                                height: 1.45,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _robotOutput(BuildContext context, List<String> output) {
    final cs = Theme.of(context).colorScheme;
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 14,
      height: 1.35,
      color: cs.onSurface,
    );

    final questionStyle = mono.copyWith(
      color: cs.primary,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w700,
    );

    final allText = output.map((e) => e.trim()).where((e) => e.isNotEmpty).join('\n');

    final visible = <({int index, String text})>[];
    for (var i = 0; i < output.length; i++) {
      final t = output[i].trim();
      if (t.isEmpty) continue;
      visible.add((index: i, text: output[i]));
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border.all(
          color: cs.primary.withOpacity(0.55),
          width: 1,
        ),
        borderRadius: BorderRadius.zero,
        boxShadow: [
          BoxShadow(
            color: cs.primary.withOpacity(0.14),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'OUTPUT',
                    style: TextStyle(
                      letterSpacing: 2.2,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy all',
                  onPressed: allText.trim().isEmpty
                      ? null
                      : () => _copyToClipboard(allText),
                  icon: const Icon(Icons.content_copy),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: cs.primary.withOpacity(0.25)),
          for (var vi = 0; vi < visible.length; vi++)
            InkWell(
              onTap: () {
                final t = visible[vi].text.trim();
                if (t.isEmpty) return;
                if (visible[vi].index == 3) {
                  final thought = _controller.text.trim();
                  if (thought.isEmpty) {
                    _copyToClipboard(t);
                    return;
                  }
                  _openReflectionSheet(thought: thought, question: t);
                  return;
                }
                _copyToClipboard(t);
              },
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, vi == 0 ? 10 : 8, 8, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: cs.primary.withOpacity(0.45),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.zero,
                      ),
                      child: Center(
                        child: Text(
                          visible[vi].index == 3
                              ? '?'
                              : '${(visible[vi].index + 1).toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        visible[vi].text,
                        style: visible[vi].index == 3 ? questionStyle : mono,
                      ),
                    ),
                    if (visible[vi].index == 3)
                      IconButton(
                        tooltip: 'Think this',
                        onPressed: () {
                          final thought = _controller.text.trim();
                          final q = visible[vi].text.trim();
                          if (thought.isEmpty || q.isEmpty) return;
                          _openReflectionSheet(thought: thought, question: q);
                        },
                        icon: Icon(
                          Icons.psychology_alt,
                          size: 18,
                          color: cs.primary,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Copy line',
                      onPressed: () {
                        final t = visible[vi].text.trim();
                        if (t.isEmpty) return;
                        _copyToClipboard(t);
                      },
                      icon: Icon(
                        Icons.copy,
                        size: 18,
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _loadEntry(ReframeEntry entry) {
    setState(() {
      _controller.text = entry.input;
      _output = entry.lines;
      _hardMode = entry.hardMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final output = _output;

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reality Reframe'),
          actions: [
            Row(
              children: [
                const Text('Hard'),
                Switch(
                  value: _hardMode,
                  onChanged: (v) async {
                    setState(() => _hardMode = v);
                    await _store.setHardMode(v);
                  },
                ),
              ],
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    TextField(
                      controller: _controller,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: 'Write the thought as-is.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _loading ? null : _runReframe,
                            child: _loading
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _RobotLoader(size: 18),
                                      SizedBox(width: 10),
                                      Text('Reframing…'),
                                    ],
                                  )
                                : const Text('Reframe'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          tooltip: 'Clear input',
                          onPressed: _loading
                              ? null
                              : () {
                                  setState(() {
                                    _controller.clear();
                                    _output = null;
                                    _error = null;
                                  });
                                },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_loading)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'building',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.7),
                          ),
                        ),
                      ),
                    if (_error != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (output != null)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.45,
                        ),
                        child: SingleChildScrollView(
                          child: _robotOutput(context, output),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('History'),
                        const Spacer(),
                        TextButton(
                          onPressed: _history.isEmpty ? null : _clearHistory,
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: _history.isEmpty
                            ? null
                            : () => _openHistoryPage(),
                        child: const Text('Open History'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openHistoryPage() {
    if (!mounted) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => _HistoryPage(
          entries: _history,
          onLoadEntry: (entry) {
            Navigator.of(context).pop();
            _loadEntry(entry);
          },
          onDeleteEntry: (id) => _deleteEntry(id),
        ),
      ),
    );
  }
}

class _HistoryPage extends StatelessWidget {
  const _HistoryPage({
    required this.entries,
    required this.onLoadEntry,
    required this.onDeleteEntry,
  });

  final List<ReframeEntry> entries;
  final void Function(ReframeEntry) onLoadEntry;
  final void Function(String) onDeleteEntry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
      ),
      body: ListView.separated(
        itemCount: entries.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return ListTile(
            title: Text(
              entry.input,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              entry.createdAt.toLocal().toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onLoadEntry(entry),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => onDeleteEntry(entry.id),
            ),
          );
        },
      ),
    );
  }
}

class _RobotLoader extends StatefulWidget {
  const _RobotLoader({required this.size});

  final double size;

  @override
  State<_RobotLoader> createState() => _RobotLoaderState();
}

class _RobotLoaderState extends State<_RobotLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onPrimary;
    final block = widget.size / 2.2;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final angle = _controller.value * 6.283185307179586;
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Transform.rotate(
            angle: angle,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: _Block(size: block, color: color.withOpacity(0.9)),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: _Block(size: block, color: color.withOpacity(0.65)),
                ),
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: _Block(size: block, color: color.withOpacity(0.65)),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _Block(size: block, color: color.withOpacity(0.9)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.zero,
      ),
    );
  }
}
