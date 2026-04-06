import 'package:flutter/material.dart';
import '../services/local_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _store = LocalStore();

  late final TextEditingController _apiController;
  late final TextEditingController _profileNameController;
  late final TextEditingController _profileTextController;
  late bool _hardMode;
  late bool _useProd;
  bool _showProfileText = false;

  @override
  void initState() {
    super.initState();
    _apiController = TextEditingController(text: _store.getApiBaseUrl());
    _profileNameController =
        TextEditingController(text: _store.getProfileName());
    _profileTextController =
        TextEditingController(text: _store.getProfileText());
    _hardMode = _store.getHardMode();
    _useProd = _store.getUseProd();
  }

  String _censoredPreview(String text, {int maxLen = 80}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    final preview = trimmed.length <= maxLen ? trimmed : trimmed.substring(0, maxLen);
    return preview.replaceAll(RegExp(r'\S'), '•');
  }

  @override
  void dispose() {
    _apiController.dispose();
    _profileNameController.dispose();
    _profileTextController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final normalized = LocalStore.normalizeApiBaseUrl(_apiController.text);
    await _store.setApiBaseUrl(normalized);
    await _store.setHardMode(_hardMode);
    await _store.setUseProd(_useProd);
    await _store.setProfileName(_profileNameController.text);
    await _store.setProfileText(_profileTextController.text);
    _apiController.text = _store.getApiBaseUrl();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
  }

  Future<void> _editBaseUrl(BuildContext context) async {
    final controller = TextEditingController();
    controller.text = _useProd
        ? 'https://web-production-e7381.up.railway.app'
        : _store.getApiBaseUrl();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit API Base URL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'http://10.0.2.2:3000',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _apiController.text = controller.text;
              Navigator.of(context).pop();
              _save();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          actions: [
            TextButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Use Production (Railway)'),
                  const Spacer(),
                  Switch(
                    value: _useProd,
                    onChanged: (v) => setState(() => _useProd = v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('API Base URL'),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _editBaseUrl(context),
                    child: const Text('Edit'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (!_useProd)
                TextField(
                  controller: _apiController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'http://10.0.2.2:3000',
                  ),
                  onSubmitted: (_) => _save(),
                ),
              if (_useProd)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'Production URL: https://web-production-e7381.up.railway.app',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'AI Profile',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _profileNameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Name (optional)',
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text('Goal / identity / context for the AI'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _showProfileText = !_showProfileText),
                    child: Text(_showProfileText ? 'Hide' : 'Reveal / Edit'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_showProfileText)
                TextField(
                  controller: _profileTextController,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Profile text',
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                    color: Theme.of(context).colorScheme.surface,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _store.hasCustomProfileText() ? 'Custom profile' : 'Default profile',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_profileTextController.text.trim().length} chars',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _censoredPreview(_profileTextController.text),
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.55),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Hidden for privacy. Tap “Reveal / Edit” to view or change it.',
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Hard Mode default'),
                  const Spacer(),
                  Switch(
                    value: _hardMode,
                    onChanged: (v) => setState(() => _hardMode = v),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
