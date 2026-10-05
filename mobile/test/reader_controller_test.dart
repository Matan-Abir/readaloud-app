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

  test('wordStartAt snaps to the start of the tapped word', () {
    const text = 'Hello brave  new world.';
    expect(wordStartAt(text, 0), 0);
    expect(wordStartAt(text, 3), 0); // inside "Hello"
    expect(wordStartAt(text, 8), 6); // inside "brave"
    expect(wordStartAt(text, 11), 13); // whitespace -> next word "new"
    expect(wordStartAt(text, 100), 17); // past the end -> last word
    expect(wordStartAt('', 5), 0);
  });

  test('tapping the current text restarts reading from that word', () async {
    final speaker = HoldingSpeaker();
    final reader = ReaderController(
      api: ApiClient(client: fakeBackend([]), baseUrl: 'http://x'),
      doc: doc(),
      speaker: speaker,
    );
    final first = reader.play();
    await pumpUntil(() => speaker.spoken.isNotEmpty);
    expect(reader.currentText, 'One.');
    expect(reader.currentOffset, 0);

    // Simulate the backend chunk at offset 5 being on screen, then tap inside it.
    reader.currentText = 'Two.';
    reader.currentOffset = 5;
    final second = reader.playFromCurrentText(2);
    await pumpUntil(() => speaker.spoken.length >= 2);
    expect(speaker.spoken.last, 'Two.');
    expect(reader.playing, isTrue);

    await reader.pause();
    await first;
    await second;
  });
}

/// Speaks until stopped, like a real engine mid-utterance.
class HoldingSpeaker implements Speaker {
  final spoken = <String>[];
  Completer<void>? _current;

  @override
  Future<void> init() async {}

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    _current = Completer<void>();
    return _current!.future;
  }

  @override
  Future<void> stop() async {
    if (!(_current?.isCompleted ?? true)) _current!.complete();
  }

  @override
  Future<void> setRate(double multiplier) async {}
}

Future<void> pumpUntil(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(done(), isTrue);
}
