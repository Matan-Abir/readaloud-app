import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'api.dart';
import 'reader_controller.dart';

/// The Piper natural voice: the server turns each sentence into audio and the
/// browser plays it. The next sentence is fetched while the current one
/// plays, so there is no pause between them.
///
/// When the server has no Piper voice, or a sentence cannot be fetched, the
/// [fallback] (the browser's own voice) reads instead.
class PiperSpeaker implements PreloadingSpeaker {
  PiperSpeaker(this.api, this.fallback);

  /// Sentences kept as ready-to-play audio.
  static const _cacheSize = 6;

  final ApiClient api;
  final Speaker fallback;

  bool _available = false;
  double _rate = 1.0;
  // Most recently used last. Values are blob: URLs of WAV audio.
  final _cache = <String, Future<String>>{};
  web.HTMLAudioElement? _audio;
  Completer<void>? _done;

  @override
  String get voiceName => _available ? 'Natural voice (Piper)' : 'Browser voice';

  @override
  Future<void> init() async {
    await fallback.init();
    try {
      _available = await api.naturalVoiceAvailable();
    } catch (_) {
      _available = false;
    }
  }

  @override
  void preload(String text) {
    if (_available) _audioUrl(text).ignore();
  }

  @override
  Future<void> speak(String text) async {
    _finish();
    if (!_available) return fallback.speak(text);
    final done = _done = Completer<void>();
    final String url;
    try {
      url = await _audioUrl(text);
    } catch (_) {
      if (done.isCompleted) return;
      _done = null;
      return fallback.speak(text);
    }
    // Stopped (pause, or a tap on another sentence) while fetching.
    if (done.isCompleted) return;

    void end(web.Event _) {
      if (!done.isCompleted) done.complete();
    }

    final audio = _audio = web.HTMLAudioElement()
      ..src = url
      ..playbackRate = _rate;
    audio.onended = end.toJS;
    audio.onerror = end.toJS;
    try {
      await audio.play().toDart;
    } catch (_) {
      // The browser refused to play it; read this sentence with its own voice.
      if (!done.isCompleted) {
        _done = null;
        _audio = null;
        return fallback.speak(text);
      }
    }
    return done.future;
  }

  @override
  Future<void> stop() async {
    _finish();
    await fallback.stop();
  }

  @override
  Future<void> setRate(double multiplier) async {
    _rate = multiplier;
    _audio?.playbackRate = multiplier;
    await fallback.setRate(multiplier);
  }

  /// The audio for [text], fetched once and reused.
  Future<String> _audioUrl(String text) {
    var url = _cache.remove(text);
    if (url == null) {
      url = api.speech(text).then((bytes) => web.URL.createObjectURL(
          web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'audio/wav'))));
      final fetched = url;
      // A failed fetch is forgotten so it can be tried again.
      fetched.then((_) {}, onError: (_) {
        if (identical(_cache[text], fetched)) _cache.remove(text);
      });
    }
    _cache[text] = url;
    while (_cache.length > _cacheSize) {
      final old = _cache.remove(_cache.keys.first)!;
      old.then((u) => web.URL.revokeObjectURL(u), onError: (_) {});
    }
    return url;
  }

  void _finish() {
    _audio?.pause();
    _audio = null;
    final done = _done;
    if (done != null && !done.isCompleted) done.complete();
    _done = null;
  }
}
