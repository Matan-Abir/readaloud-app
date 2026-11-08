import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'api.dart';
import 'piper_speaker.dart';
import 'reader_controller.dart';

/// The browser's own speech engine, used directly.
///
/// flutter_tts on the web reuses one utterance and one completer, so stopping
/// a sentence and starting another right away (a tap on the text) can skip
/// the new sentence or hang. Here each sentence gets its own utterance and
/// its own completion.
class WebSpeaker implements Speaker {
  double _rate = 1.0;
  // Held only to keep it alive: Chrome can drop events of collected utterances.
  // ignore: unused_field
  web.SpeechSynthesisUtterance? _utterance;
  Completer<void>? _done;

  web.SpeechSynthesis get _synth => web.window.speechSynthesis;

  @override
  Future<void> init() async {}

  @override
  Future<void> speak(String text) {
    _finish();
    final done = _done = Completer<void>();
    void end(web.Event _) {
      if (!done.isCompleted) done.complete();
    }

    final u = _utterance = web.SpeechSynthesisUtterance(text)
      ..lang = 'en-US'
      ..rate = _rate;
    u.onend = end.toJS;
    u.onerror = end.toJS;
    _synth.speak(u);
    return done.future;
  }

  @override
  Future<void> stop() async {
    _synth.cancel();
    _finish();
  }

  @override
  Future<void> setRate(double multiplier) async => _rate = multiplier;

  void _finish() {
    final done = _done;
    if (done != null && !done.isCompleted) done.complete();
    _done = null;
    _utterance = null;
  }
}

/// In the browser: the server's Piper voice when it has one, otherwise the
/// browser's own voice.
Speaker createPlatformSpeaker(ApiClient api) => PiperSpeaker(api, WebSpeaker());
