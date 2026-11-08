import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'api.dart';
import 'reading_text.dart';

/// Speech engine abstraction so the reader logic can be tested without a device.
abstract class Speaker {
  Future<void> init();

  /// Completes when the utterance finishes (or is stopped).
  Future<void> speak(String text);
  Future<void> stop();
  Future<void> setRate(double multiplier);
}

/// Extras for speakers that fetch their audio, like the Piper voice.
abstract interface class PreloadingSpeaker implements Speaker {
  /// Shown under the player, e.g. "Natural voice (Piper)".
  String get voiceName;

  /// Starts fetching [text] now so it can play without a pause later.
  void preload(String text);
}

class DeviceSpeaker implements Speaker {
  final FlutterTts _tts = FlutterTts();

  @override
  Future<void> init() async {
    await _tts.awaitSpeakCompletion(true);
    await _tts.setLanguage('en-US');
  }

  @override
  Future<void> speak(String text) => _tts.speak(text);

  @override
  Future<void> stop() => _tts.stop();

  // flutter_tts on Android treats ~0.5 as normal speed.
  @override
  Future<void> setRate(double multiplier) => _tts.setSpeechRate((0.5 * multiplier).clamp(0.1, 1.0));
}

/// Loads a document's text, reads it aloud one sentence at a time, remembers
/// which sentence is being read, and saves progress on the server so listening
/// can resume anywhere.
class ReaderController extends ChangeNotifier {
  ReaderController({
    required this.api,
    required this.doc,
    required this.speaker,
    this.pageSize = 50,
  });

  final ApiClient api;
  final DocumentInfo doc;
  final Speaker speaker;
  final int pageSize;

  ReadingText? content;
  bool loading = false;
  double loaded = 0;

  /// Index of the sentence being read (or that will be read on play).
  int current = 0;
  bool playing = false;
  bool finished = false;
  String? error;
  String? voiceName;
  double speed = 1.0;
  int _generation = 0;

  int get sentenceCount => content?.sentences.length ?? 0;

  double get progress {
    final c = content;
    if (c == null || doc.textLength == 0 || c.sentences.isEmpty) return 0;
    return (c.sourceOffset(c.sentences[current].start) / doc.textLength).clamp(0.0, 1.0);
  }

  /// Loads the whole document text and prepares the voice.
  Future<void> init() async {
    await Future.wait([load(), _initSpeaker()]);
  }

  Future<void> _initSpeaker() async {
    try {
      await speaker.init();
      await speaker.setRate(speed);
    } catch (_) {
      // Some browsers refuse voice settings before the first user gesture;
      // speaking still works with the defaults.
    }
    final s = speaker;
    if (s is PreloadingSpeaker) {
      voiceName = s.voiceName;
      notifyListeners();
    }
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    error = null;
    loaded = 0;
    notifyListeners();
    try {
      final chunks = <TextChunk>[];
      var start = 0;
      while (true) {
        final page = await api.chunks(doc.id, start: start, limit: pageSize);
        if (page.isEmpty) break;
        chunks.addAll(page);
        start = page.last.offset + page.last.text.length;
        if (doc.textLength > 0) loaded = (start / doc.textLength).clamp(0.0, 1.0);
        notifyListeners();
      }
      final c = ReadingText.fromChunks(chunks);
      content = c;
      current = c.sentences.isEmpty ? 0 : c.sentenceAtSource(doc.progressChar);
    } on ApiException catch (e) {
      error = e.message;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> play() async {
    final c = content;
    if (playing || c == null || c.sentences.isEmpty) return;
    if (finished) current = 0;
    playing = true;
    finished = false;
    error = null;
    final gen = ++_generation;
    notifyListeners();

    while (playing && gen == _generation) {
      if (current >= c.sentences.length) {
        finished = true;
        current = 0;
        _saveProgress(0);
        break;
      }
      _saveProgress(c.sourceOffset(c.sentences[current].start));
      _preload(current + 1);
      await speaker.speak(c.sentenceText(current));
      if (gen != _generation) return;
      current++;
      if (current < c.sentences.length) notifyListeners();
    }
    if (gen == _generation) {
      playing = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    if (!playing) return;
    playing = false;
    _generation++;
    await speaker.stop();
    notifyListeners();
  }

  /// Moves to sentence [index] and keeps playing if we were.
  Future<void> jumpTo(int index) async {
    final wasPlaying = playing;
    await _moveTo(index);
    if (wasPlaying) await play();
  }

  /// Starts reading from sentence [index] (used when the user taps text).
  Future<void> playFrom(int index) async {
    await _moveTo(index);
    await play();
  }

  Future<void> _moveTo(int index) async {
    final c = content;
    if (c == null || c.sentences.isEmpty) return;
    await pause();
    current = index.clamp(0, c.sentences.length - 1);
    finished = false;
    _saveProgress(c.sourceOffset(c.sentences[current].start));
    notifyListeners();
  }

  Future<void> setSpeed(double multiplier) async {
    speed = multiplier;
    await speaker.setRate(multiplier);
    notifyListeners();
  }

  /// Lets a fetching speaker get the next sentence ready while this one plays.
  void _preload(int index) {
    final c = content;
    final s = speaker;
    if (s is PreloadingSpeaker && c != null && index < c.sentences.length) {
      s.preload(c.sentenceText(index));
    }
  }

  void _saveProgress(int value) {
    // Best effort; a failed save must not interrupt listening.
    api.saveProgress(doc.id, value).catchError((_) {});
  }

  @override
  void dispose() {
    _generation++;
    playing = false;
    speaker.stop();
    super.dispose();
  }
}
