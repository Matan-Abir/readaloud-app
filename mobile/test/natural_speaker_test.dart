import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readaloud/api.dart';
import 'package:readaloud/natural_speaker.dart';
import 'package:readaloud/reader_controller.dart';
import 'package:readaloud/screens/reader_screen.dart';

import 'reader_controller_test.dart' show FakeSpeaker;

class FakeOut implements AudioOut {
  final played = <String>[];
  Completer<void>? _current;
  bool hold = false;

  @override
  Future<void> play(Uint8List wav) {
    played.add(String.fromCharCodes(wav));
    if (!hold) return Future.value();
    _current = Completer<void>();
    return _current!.future;
  }

  @override
  Future<void> stop() async {
    if (!(_current?.isCompleted ?? true)) _current!.complete();
  }
}

Uint8List wav(String s) => Uint8List.fromList(s.codeUnits);

void main() {
  test('splitSentences splits on sentence ends and caps long sentences', () {
    expect(splitSentences('One. Two!  Three? Four'), ['One.', 'Two!', 'Three?', 'Four']);
    expect(splitSentences('Line one\nLine two.'), ['Line one', 'Line two.']);
    expect(splitSentences('aaaa bbbb cccc', maxLen: 9), ['aaaa bbbb', 'cccc']);
    expect(splitSentences('   '), isEmpty);
  });

  test('speaks each sentence in order at the chosen speed', () async {
    final asked = <String>[];
    final out = FakeOut();
    final speaker = NaturalSpeaker(
      synthesize: (text, speed) async {
        asked.add('$text@$speed');
        return wav(text);
      },
      out: out,
    );
    await speaker.setRate(1.5);
    await speaker.speak('Hello there. How are you?');
    expect(out.played, ['Hello there.', 'How are you?']);
    expect(asked, ['Hello there.@1.5', 'How are you?@1.5']);
  });

  test('stop ends the current utterance and plays nothing more', () async {
    final out = FakeOut()..hold = true;
    final speaker = NaturalSpeaker(synthesize: (text, _) async => wav(text), out: out);
    final speaking = speaker.speak('First. Second. Third.');
    await Future<void>.delayed(Duration.zero);
    expect(out.played, ['First.']);
    await speaker.stop();
    await speaking;
    expect(out.played, ['First.']);
  });

  test('falls back to the device voice when the server fails', () async {
    var fellBack = false;
    final device = FakeSpeaker();
    final speaker = FallbackSpeaker(
      primary: NaturalSpeaker(synthesize: (_, _) async => throw Exception('down'), out: FakeOut()),
      secondary: device,
      onFallback: () => fellBack = true,
    );
    await speaker.speak('Hello.');
    await speaker.speak('Again.');
    expect(fellBack, isTrue);
    expect(device.spoken, ['Hello.', 'Again.']);
  });

  test('VoiceChoice picks the natural voice when the server offers it', () async {
    final api = ApiClient(
      baseUrl: 'http://x',
      client: MockClient((req) async => req.url.path == '/api/tts'
          ? http.Response(jsonEncode({'available': true, 'voice': 'en_US-lessac-medium'}), 200)
          : http.Response('{}', 200)),
    );
    final device = FakeSpeaker();
    final reader = ReaderController(
      api: api,
      doc: DocumentInfo(id: 1, title: 't', pageCount: 1, textLength: 10, progressChar: 0),
      speaker: device,
    );
    final voice = VoiceChoice(reader);
    await voice.detect(api, device);
    expect(voice.available, isTrue);
    expect(voice.natural, isTrue);
    expect(voice.voiceName, 'en_US-lessac-medium');
    expect(reader.speaker, isA<FallbackSpeaker>());

    await voice.setNatural(false);
    expect(reader.speaker, same(device));
  });

  test('VoiceChoice keeps the device voice when the server has none', () async {
    final api = ApiClient(
      baseUrl: 'http://x',
      client: MockClient((_) async => http.Response(jsonEncode({'available': false, 'voice': null}), 200)),
    );
    final device = FakeSpeaker();
    final reader = ReaderController(
      api: api,
      doc: DocumentInfo(id: 1, title: 't', pageCount: 1, textLength: 10, progressChar: 0),
      speaker: device,
    );
    final voice = VoiceChoice(reader);
    await voice.detect(api, device);
    expect(voice.available, isFalse);
    expect(reader.speaker, same(device));
  });
}

