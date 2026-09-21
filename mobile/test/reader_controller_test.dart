import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readaloud/api.dart';
import 'package:readaloud/reader_controller.dart';

class FakeSpeaker implements Speaker {
  final spoken = <String>[];
  double rate = 1.0;

  @override
  Future<void> init() async {}

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async {}

  @override
  Future<void> setRate(double multiplier) async => rate = multiplier;
}

/// Serves a 3-chunk document and records progress saves.
http.Client fakeBackend(List<int> saved) {
  const chunks = [
    {'offset': 0, 'text': 'One.'},
    {'offset': 5, 'text': 'Two.'},
    {'offset': 10, 'text': 'Three.'},
  ];
  return MockClient((req) async {
    if (req.url.path.endsWith('/chunks')) {
      final start = int.parse(req.url.queryParameters['start'] ?? '0');
      final rest = chunks.where((c) => (c['offset'] as int) >= start).toList();
      return http.Response(jsonEncode({'chunks': rest, 'text_length': 16}), 200);
    }
    if (req.url.path.endsWith('/progress')) {
      saved.add(jsonDecode(req.body)['progress_char'] as int);
      return http.Response('{}', 200);
    }
    return http.Response('{"error":"nope"}', 404);
  });
}

DocumentInfo doc({int progress = 0}) => DocumentInfo(
    id: 1, title: 't', pageCount: 1, textLength: 16, progressChar: progress);

void main() {
  test('plays every chunk in order, saves progress, then finishes', () async {
    final saved = <int>[];
    final speaker = FakeSpeaker();
    final reader = ReaderController(
      api: ApiClient(client: fakeBackend(saved), baseUrl: 'http://x'),
      doc: doc(),
      speaker: speaker,
    );
    await reader.play();
    await Future<void>.delayed(Duration.zero); // let fire-and-forget saves land
    expect(speaker.spoken, ['One.', 'Two.', 'Three.']);
    expect(reader.finished, isTrue);
    expect(reader.playing, isFalse);
    expect(saved.take(3), [0, 5, 10]);
    expect(saved.last, 0); // reset after finishing
  });

  test('resumes from saved progress', () async {
    final speaker = FakeSpeaker();
    final reader = ReaderController(
      api: ApiClient(client: fakeBackend([]), baseUrl: 'http://x'),
      doc: doc(progress: 5),
      speaker: speaker,
    );
    await reader.play();
    expect(speaker.spoken, ['Two.', 'Three.']);
  });

  test('reports server errors instead of throwing', () async {
    final reader = ReaderController(
      api: ApiClient(
        client: MockClient((_) async => http.Response('{"error":"boom"}', 500)),
        baseUrl: 'http://x',
      ),
      doc: doc(),
      speaker: FakeSpeaker(),
    );
    await reader.play();
    expect(reader.error, 'boom');
    expect(reader.playing, isFalse);
  });

  test('speed change is forwarded to the speaker', () async {
    final speaker = FakeSpeaker();
    final reader = ReaderController(
      api: ApiClient(client: fakeBackend([]), baseUrl: 'http://x'),
      doc: doc(),
      speaker: speaker,
    );
    await reader.setSpeed(1.5);
    expect(speaker.rate, 1.5);
  });
}
