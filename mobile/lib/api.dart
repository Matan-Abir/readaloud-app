import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);

  @override
  String toString() => message;
}

class DocumentInfo {
  final int id;
  final String title;
  final int pageCount;
  final int textLength;
  final int progressChar;

  DocumentInfo({
    required this.id,
    required this.title,
    required this.pageCount,
    required this.textLength,
    required this.progressChar,
  });

  factory DocumentInfo.fromJson(Map<String, dynamic> j) => DocumentInfo(
        id: j['id'] as int,
        title: j['title'] as String,
        pageCount: (j['page_count'] ?? 0) as int,
        textLength: (j['text_length'] ?? 0) as int,
        progressChar: (j['progress_char'] ?? 0) as int,
      );

  double get progress => textLength == 0 ? 0 : progressChar / textLength;
}

class TextChunk {
  final int offset;
  final String text;
  TextChunk(this.offset, this.text);
}

class QaEntry {
  final String question;
  final String answer;
  QaEntry(this.question, this.answer);
}

class ApiClient extends ChangeNotifier {
  ApiClient({http.Client? client, String? baseUrl})
      : _http = client ?? http.Client(),
        _base = baseUrl ?? apiBaseUrl;

  static const _tokenKey = 'access_token';
  final http.Client _http;
  final String _base;
  String? _token;

  bool get loggedIn => _token != null;

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    notifyListeners();
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_base$path').replace(queryParameters: query);

  dynamic _decode(http.Response r) {
    dynamic body;
    try {
      body = r.body.isEmpty ? null : jsonDecode(r.body);
    } catch (_) {
      body = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    final msg = body is Map && body['error'] != null
        ? body['error'].toString()
        : (body is Map && body['msg'] != null ? body['msg'].toString() : 'Request failed (${r.statusCode})');
    if (r.statusCode == 401) {
      // Expired/invalid token on an authenticated call: force re-login.
      if (_token != null) logout();
    }
    throw ApiException(msg, r.statusCode);
  }

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    try {
      return _decode(await call().timeout(const Duration(seconds: 90)));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Cannot reach the server. Check your connection.');
    }
  }

  Future<void> register(String email, String password) async {
    await _send(() => _http.post(_uri('/api/auth/register'),
        headers: _headers, body: jsonEncode({'email': email, 'password': password})));
    await login(email, password);
  }

  Future<void> login(String email, String password) async {
    final body = await _send(() => _http.post(_uri('/api/auth/login'),
        headers: _headers, body: jsonEncode({'email': email, 'password': password})));
    _token = body['access_token'] as String;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, _token!);
    notifyListeners();
  }

  Future<List<DocumentInfo>> listDocuments() async {
    final body = await _send(() => _http.get(_uri('/api/documents'), headers: _headers));
    return (body as List).map((e) => DocumentInfo.fromJson(e)).toList();
  }

  Future<DocumentInfo> uploadDocument(String filename, List<int> bytes) async {
    final req = http.MultipartRequest('POST', _uri('/api/documents'))
      ..headers['Authorization'] = 'Bearer $_token'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final body = await _send(() async => http.Response.fromStream(await _http.send(req)));
    return DocumentInfo.fromJson(body);
  }

  Future<void> deleteDocument(int id) async {
    await _send(() => _http.delete(_uri('/api/documents/$id'), headers: _headers));
  }

  Future<DocumentInfo> getDocument(int id) async {
    final body = await _send(() => _http.get(_uri('/api/documents/$id'), headers: _headers));
    return DocumentInfo.fromJson(body);
  }

  Future<List<TextChunk>> chunks(int id, {int? start, int limit = 5}) async {
    final body = await _send(() => _http.get(
        _uri('/api/documents/$id/chunks',
            {'limit': '$limit', if (start != null) 'start': '$start'}),
        headers: _headers));
    return (body['chunks'] as List)
        .map((c) => TextChunk(c['offset'] as int, c['text'] as String))
        .toList();
  }

  Future<void> saveProgress(int id, int progressChar) async {
    await _send(() => _http.put(_uri('/api/documents/$id/progress'),
        headers: _headers, body: jsonEncode({'progress_char': progressChar})));
  }

  Future<String> summarize(int id) async {
    final body = await _send(() => _http.post(_uri('/api/documents/$id/summarize'), headers: _headers));
    return body['summary'] as String;
  }

  Future<QaEntry> ask(int id, String question) async {
    final body = await _send(() => _http.post(_uri('/api/documents/$id/ask'),
        headers: _headers, body: jsonEncode({'question': question})));
    return QaEntry(body['question'] as String, body['answer'] as String);
  }

  Future<List<QaEntry>> history(int id) async {
    final body = await _send(() => _http.get(_uri('/api/documents/$id/history'), headers: _headers));
    return (body as List).map((e) => QaEntry(e['question'] as String, e['answer'] as String)).toList();
  }
}
