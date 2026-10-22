import 'dart:async';
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

/// Serves a small document (server text "One. Two.\nThree.\n\nFour.") in
/// pages of two chunks, and records progress saves.
http.Client fakeBackend(List<int> saved) {
  const chunks = [
    {'offset': 0, 'text': 'One. Two.'},
    {'offset': 9, 'text': 'Three.'},
    {'offset': 17, 'text': 'Four.'},
  ];
  return MockClient((req) async {
    if (req.url.path.endsWith('/chunks')) {
      final start = int.parse(req.url.queryParameters['start'] ?? '0');
      final limit = int.parse(req.url.queryParameters['limit'] ?? '5');
      final rest = chunks.where((c) => (c['offset'] as int) >= start).take(limit).toList();
      return http.Response(jsonEncode({'chunks': rest, 'text_length': 22}), 200);
    }
    if (req.url.path.endsWith('/progress')) {
      saved.add(jsonDecode(req.body)['progress_char'] as int);
      return http.Response('{}', 200);
    }
    return http.Response('{"error":"nope"}', 404);
  });
}

/// Completes each utterance only when told to, so tests can act mid-sentence.
class HoldingSpeaker extends FakeSpeaker {
  Completer<void>? _pending;

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    return (_pending = Completer<void>()).future;
  }

  void finish() => _pending?.complete();

  @override
  Future<void> stop() async => finish();
}

/// Records which sentences it was asked to fetch ahead of time.
class PreloadSpeaker extends FakeSpeaker implements PreloadingSpeaker {
  final preloaded = <String>[];

  @override
  String get voiceName => 'Test voice';

  @override
  void preload(String text) => preloaded.add(text);
}

DocumentInfo doc({int progress = 0}) => DocumentInfo(
    id: 1, title: 't', pageCount: 1, textLength: 22, progressChar: progress);

Future<ReaderController> ready(Speaker speaker, {int progress = 0, List<int>? saved}) async {
  final reader = ReaderController(
    api: ApiClient(client: fakeBackend(saved ?? []), baseUrl: 'http://x'),
    doc: doc(progress: progress),
    speaker: speaker,
    pageSize: 2,
  );
  await reader.init();
  return reader;
}

void main() {
  test('loads the whole document across pages and splits it into sentences', () async {
    final reader = await ready(FakeSpeaker());
    expect(reader.content!.text, 'One. Two. Three.\n\nFour.');
    expect(reader.sentenceCount, 4);
    expect(reader.loading, isFalse);
  });

  test('reads sentence by sentence, saves progress, then finishes', () async {
    final saved = <int>[];
    final speaker = FakeSpeaker();
    final reader = await ready(speaker, saved: saved);
    await reader.play();
    await Future<void>.delayed(Duration.zero); // let fire-and-forget saves land
    expect(speaker.spoken, ['One.', 'Two.', 'Three.', 'Four.']);
    expect(reader.finished, isTrue);
    expect(reader.playing, isFalse);
    expect(saved, [0, 5, 9, 17, 0]);
  });

  test('resumes from the sentence holding the saved progress', () async {
    final speaker = FakeSpeaker();
    final reader = await ready(speaker, progress: 10);
    expect(reader.current, 2);
    await reader.play();
    expect(speaker.spoken, ['Three.', 'Four.']);
  });

  test('tapping a sentence while reading restarts from it', () async {
    final speaker = HoldingSpeaker();
    final reader = await ready(speaker);
    final playing = reader.play();
    await Future<void>.delayed(Duration.zero);
    expect(speaker.spoken, ['One.']);

    final tapped = reader.playFrom(3);
    await Future<void>.delayed(Duration.zero);
    expect(reader.current, 3);
    expect(speaker.spoken, ['One.', 'Four.']);
    speaker.finish();
    await Future.wait([playing, tapped]);
    expect(reader.finished, isTrue);
  });

  test('next and previous move one sentence while paused', () async {
    final reader = await ready(FakeSpeaker());
    await reader.jumpTo(reader.current + 1);
    expect(reader.current, 1);
    await reader.jumpTo(reader.current - 1);
    await reader.jumpTo(reader.current - 1);
    expect(reader.current, 0);
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
    await reader.init();
    expect(reader.error, 'boom');
    expect(reader.content, isNull);
    await reader.play(); // nothing to play, must not throw
    expect(reader.playing, isFalse);
  });

  test('speed change is forwarded to the speaker', () async {
    final speaker = FakeSpeaker();
    final reader = await ready(speaker);
    await reader.setSpeed(1.5);
    expect(speaker.rate, 1.5);
  });

  test('a preloading speaker gets each next sentence ahead of time', () async {
    final speaker = PreloadSpeaker();
    final reader = await ready(speaker);
    expect(reader.voiceName, 'Test voice');
    await reader.play();
    expect(speaker.spoken, ['One.', 'Two.', 'Three.', 'Four.']);
    expect(speaker.preloaded, ['Two.', 'Three.', 'Four.']);
  });
}
