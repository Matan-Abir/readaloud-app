import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'api.dart';

/// Speech engine abstraction so the reader logic can be tested without a device.
abstract class Speaker {
  Future<void> init();

  /// Completes when the utterance finishes (or is stopped).
  Future<void> speak(String text);
  Future<void> stop();
  Future<void> setRate(double multiplier);
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

/// Start of the word containing [index] in [text] (or of the next word when
/// [index] falls on whitespace), so a tap lands on a whole word.
int wordStartAt(String text, int index) {
  if (text.isEmpty) return 0;
  var i = index.clamp(0, text.length - 1);
  bool isSpace(int at) => text[at].trim().isEmpty;
  if (isSpace(i)) {
    while (i < text.length && isSpace(i)) {
      i++;
    }
    return i.clamp(0, text.length - 1);
  }
  while (i > 0 && !isSpace(i - 1)) {
    i--;
  }
  return i;
}

/// Streams a document's text chunks to the speech engine, remembers where the
/// user is, and saves progress on the server so listening can resume anywhere.
class ReaderController extends ChangeNotifier {
  ReaderController({
    required this.api,
    required this.doc,
    required this.speaker,
    this.batchSize = 5,
  }) : _offset = doc.progressChar;

  final ApiClient api;
  final DocumentInfo doc;
  Speaker speaker;
  final int batchSize;

  final List<TextChunk> _buffer = [];
  int _offset;
  int _fetchFrom = 0;
  int _generation = 0;
  String currentText = '';

  /// Document offset of the first character of [currentText].
  int currentOffset = 0;
  bool playing = false;
  bool finished = false;
  String? error;
  double speed = 1.0;

  double get progress => doc.textLength == 0 ? 0 : (_offset / doc.textLength).clamp(0.0, 1.0);

  Future<void> init() => speaker.init();

  Future<void> play() async {
    if (playing) return;
    playing = true;
    finished = false;
    error = null;
    final gen = ++_generation;
    _buffer.clear();
    _fetchFrom = _offset;
    notifyListeners();

    try {
      while (playing && gen == _generation) {
        if (_buffer.isEmpty) {
          final next = await api.chunks(doc.id, start: _fetchFrom, limit: batchSize);
          if (gen != _generation) return;
          if (next.isEmpty) {
            finished = true;
            _offset = 0;
            currentText = '';
            _saveProgress(0);
            break;
          }
          _buffer.addAll(next);
          final last = next.last;
          _fetchFrom = last.offset + last.text.length;
        }
        final chunk = _buffer.removeAt(0);
        _offset = chunk.offset;
        currentOffset = chunk.offset;
        currentText = chunk.text;
        notifyListeners();
        _saveProgress(_offset);
        await speaker.speak(chunk.text);
        if (gen != _generation) return;
        _offset = chunk.offset + chunk.text.length;
      }
    } on ApiException catch (e) {
      if (gen == _generation) error = e.message;
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
    _buffer.clear();
    await speaker.stop();
    notifyListeners();
  }

  /// Jump by roughly [chars] characters (negative = back) and keep playing if we were.
  Future<void> seek(int chars) async {
    final wasPlaying = playing;
    await pause();
    _offset = (_offset + chars).clamp(0, doc.textLength);
    notifyListeners();
    if (wasPlaying) await play();
  }

  /// Start reading from the word at [index] within [currentText]. Restarts
  /// playback if it was running, and starts it if it wasn't.
  Future<void> playFromCurrentText(int index) async {
    if (currentText.isEmpty) return;
    await pause();
    _offset = (currentOffset + wordStartAt(currentText, index)).clamp(0, doc.textLength);
    finished = false;
    notifyListeners();
    await play();
  }

  /// Swap the voice (e.g. natural <-> device), continuing from the current
  /// passage if it was playing.
  Future<void> useSpeaker(Speaker next) async {
    if (identical(next, speaker)) return;
    final wasPlaying = playing;
    await pause();
    speaker = next;
    await speaker.init();
    await speaker.setRate(speed);
    notifyListeners();
    if (wasPlaying) await play();
  }

  Future<void> setSpeed(double multiplier) async {
    speed = multiplier;
    await speaker.setRate(multiplier);
    notifyListeners();
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
