import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'reader_controller.dart';

/// Split [text] into sentences for per-sentence synthesis. Sentences longer
/// than [maxLen] are cut at the last space before the limit.
List<String> splitSentences(String text, {int maxLen = 400}) {
  final out = <String>[];
  for (final raw in text.split(RegExp(r'(?<=[.!?…])\s+|\n+'))) {
    var s = raw.trim();
    while (s.length > maxLen) {
      var cut = s.lastIndexOf(' ', maxLen);
      if (cut <= 0) cut = maxLen;
      out.add(s.substring(0, cut).trim());
      s = s.substring(cut).trim();
    }
    if (s.isNotEmpty) out.add(s);
  }
  return out;
}

/// Plays one WAV clip at a time; [play] completes when the clip ends or is stopped.
abstract class AudioOut {
  Future<void> play(Uint8List wav);
  Future<void> stop();
}

class PlayerAudioOut implements AudioOut {
  AudioPlayer? _player; // created on first use, so nothing touches the platform until playback
  Completer<void>? _done;

  @override
  Future<void> play(Uint8List wav) async {
    final player = _player ??= AudioPlayer();
    final done = _done = Completer<void>();
    final sub = player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    try {
      await player.play(BytesSource(wav, mimeType: 'audio/wav'));
      await done.future;
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<void> stop() async {
    await _player?.stop();
    if (!(_done?.isCompleted ?? true)) _done!.complete();
  }
}

typedef Synthesize = Future<Uint8List> Function(String text, double speed);

/// Natural voice: synthesizes each sentence on the server (Piper) and plays
/// it, fetching the next sentence while the current one is playing.
class NaturalSpeaker implements Speaker {
  NaturalSpeaker({required this.synthesize, AudioOut? out}) : _out = out ?? PlayerAudioOut();

  final Synthesize synthesize;
  final AudioOut _out;
  double _speed = 1.0;
  int _generation = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> speak(String text) async {
    final gen = ++_generation;
    final sentences = splitSentences(text);
    if (sentences.isEmpty) return;
    var next = _fetch(sentences.first);
    for (var i = 0; i < sentences.length; i++) {
      final audio = await next;
      if (gen != _generation) return;
      if (i + 1 < sentences.length) next = _fetch(sentences[i + 1]);
      await _out.play(audio);
      if (gen != _generation) return;
    }
  }

  /// Start synthesizing now; a prefetch that's dropped after a stop must not
  /// surface as an unhandled error (awaiting it still rethrows).
  Future<Uint8List> _fetch(String sentence) => synthesize(sentence, _speed)..ignore();

  @override
  Future<void> stop() async {
    _generation++;
    await _out.stop();
  }

  @override
  Future<void> setRate(double multiplier) async => _speed = multiplier;
}

/// Uses [primary] until it fails once, then [secondary] for good (e.g. the
/// natural-voice server is down -> fall back to the device's voice).
class FallbackSpeaker implements Speaker {
  FallbackSpeaker({required this.primary, required this.secondary, this.onFallback});

  final Speaker primary;
  final Speaker secondary;
  final VoidCallback? onFallback;
  bool failed = false;

  @override
  Future<void> init() async {
    await primary.init();
    await secondary.init();
  }

  @override
  Future<void> speak(String text) async {
    if (!failed) {
      try {
        return await primary.speak(text);
      } catch (_) {
        failed = true;
        onFallback?.call();
      }
    }
    await secondary.speak(text);
  }

  @override
  Future<void> stop() async {
    await primary.stop();
    await secondary.stop();
  }

  @override
  Future<void> setRate(double multiplier) async {
    await primary.setRate(multiplier);
    await secondary.setRate(multiplier);
  }
}
