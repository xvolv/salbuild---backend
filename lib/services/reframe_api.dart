import 'dart:convert';

import 'package:http/http.dart' as http;

class ReframeApi {
  ReframeApi({required this.baseUrl});

  final String baseUrl;

  Future<List<String>> reframe({
    required String text,
    required bool hardMode,
    String? profileName,
    String? profileText,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/reframe');

    // Increased timeout to 90 seconds as AI providers can sometimes be slow.
    final resp = await http
        .post(
          uri,
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'text': text,
            'hardMode': hardMode,
            if (profileName != null && profileName.trim().isNotEmpty)
              'profileName': profileName.trim(),
            if (profileText != null && profileText.trim().isNotEmpty)
              'profileText': profileText.trim(),
          }),
        )
        .timeout(const Duration(seconds: 90));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      // Check if the response is JSON or plain text
      String errorMessage = resp.body;
      try {
        final decodedError = jsonDecode(resp.body);
        if (decodedError is Map && decodedError.containsKey('error')) {
          final err = decodedError['error']?.toString() ?? 'error';
          if (err == 'rate_limited') {
            final provider = decodedError['provider']?.toString() ?? '';
            final retry = decodedError['retryAfterSeconds']?.toString() ?? '';
            throw Exception('rate_limited|$provider|$retry');
          }
          errorMessage = err;
          if (decodedError.containsKey('message')) {
            errorMessage += ': ${decodedError['message']}';
          }
        }
      } catch (_) {
        // Not JSON, keep original body
      }
      throw Exception('Server Error: $errorMessage');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is Map && decoded['lines'] is List) {
      final lines = (decoded['lines'] as List).map((e) => e.toString()).toList();
      return lines;
    }

    throw Exception('Unexpected response format from server');
  }

  Future<String> reflect({
    required String text,
    required String question,
    required bool hardMode,
    String? profileName,
    String? profileText,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/reframe_reflect');
    final resp = await http
        .post(
          uri,
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'text': text,
            'question': question,
            'hardMode': hardMode,
            if (profileName != null && profileName.trim().isNotEmpty)
              'profileName': profileName.trim(),
            if (profileText != null && profileText.trim().isNotEmpty)
              'profileText': profileText.trim(),
          }),
        )
        .timeout(const Duration(seconds: 90));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String errorMessage = resp.body;
      try {
        final decodedError = jsonDecode(resp.body);
        if (decodedError is Map && decodedError.containsKey('error')) {
          final err = decodedError['error']?.toString() ?? 'error';
          if (err == 'rate_limited') {
            final provider = decodedError['provider']?.toString() ?? '';
            final retry = decodedError['retryAfterSeconds']?.toString() ?? '';
            throw Exception('rate_limited|$provider|$retry');
          }
          errorMessage = err;
          if (decodedError.containsKey('message')) {
            errorMessage += ': ${decodedError['message']}';
          }
        }
      } catch (_) {}
      throw Exception('Server Error: $errorMessage');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is Map && decoded['reflection'] is String) {
      return (decoded['reflection'] as String).trim();
    }

    throw Exception('Unexpected response format from server');
  }
}
