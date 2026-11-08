import 'dart:typed_data';

import 'api.dart';

/// One sentence of the document: a range of [ReadingText.text].
class Sentence {
  const Sentence(this.start, this.end);
  final int start;
  final int end;
}

/// A run of sentences shown as one block of text on screen.
class Block {
  const Block(this.first, this.last, {required this.paragraphEnd});

  /// Index of the first and last sentence (inclusive).
  final int first;
  final int last;

  /// True when a real paragraph break follows this block.
  final bool paragraphEnd;
}

/// The whole document, cleaned up for reading and listening.
///
/// PDF text arrives with a hard line break at the end of every printed line.
/// Here those wraps are joined into flowing text (words hyphenated across a
/// wrap are rejoined), and blank lines are kept as paragraph breaks. Every
/// character remembers where it came from in the server's text, so saved
/// progress offsets stay meaningful.
class ReadingText {
  ReadingText._(this.text, this._source, this.sentences, this.blocks);

  final String text;
  final Int32List _source;
  final List<Sentence> sentences;
  final List<Block> blocks;

  /// Offset in the server's text of [index] in [text].
  int sourceOffset(int index) =>
      _source.isEmpty ? 0 : _source[index.clamp(0, _source.length - 1)];

  String sentenceText(int i) => text.substring(sentences[i].start, sentences[i].end);

  /// The sentence containing server offset [offset] (or the next one after it).
  int sentenceAtSource(int offset) {
    var lo = 0, hi = sentences.length - 1;
    if (hi < 0) return 0;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (sourceOffset(sentences[mid].start) <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Builds the text from the server's chunks, in order.
  factory ReadingText.fromChunks(List<TextChunk> chunks,
      {int maxSentence = 300, int maxBlock = 1500}) {
    // Glue the chunks back together. The server strips whitespace at chunk
    // edges, so a gap of two or more characters was a paragraph break.
    final raw = StringBuffer();
    final rawSource = <int>[];
    var end = 0;
    for (final c in chunks) {
      if (raw.isNotEmpty) {
        final sep = c.offset - end >= 2 ? '\n\n' : ' ';
        raw.write(sep);
        rawSource.addAll(List.filled(sep.length, end));
      }
      raw.write(c.text);
      for (var j = 0; j < c.text.length; j++) {
        rawSource.add(c.offset + j);
      }
      end = c.offset + c.text.length;
    }
    final (text, source) = _joinLines(raw.toString(), rawSource);
    final sentences = _splitSentences(text, maxSentence);
    final blocks = _groupBlocks(text, sentences, maxBlock);
    return ReadingText._(text, source, sentences, blocks);
  }
}

final _space = RegExp(r'\s');
final _word = RegExp(r'[A-Za-z0-9]');

/// Joins wrapped lines into flowing text and keeps paragraph breaks ("\n\n").
/// Returns the new text and, per character, its source offset.
///
/// PDF extraction usually drops blank lines, so a line break also counts as a
/// paragraph break when the line before it is clearly shorter than a full
/// line (the end of a paragraph, or a heading). A page break in the middle of
/// a sentence is joined like any other wrap.
(String, Int32List) _joinLines(String raw, List<int> rawSource) {
  final out = StringBuffer();
  final source = <int>[];
  final shortLine = _typicalLineLength(raw) * 0.6;
  var lineStart = 0;
  var i = 0;
  while (i < raw.length) {
    final ch = raw[i];
    if (!_space.hasMatch(ch)) {
      // "exam-\nple" -> "example"
      if (ch == '-' && i > 0 && _word.hasMatch(raw[i - 1])) {
        var j = i + 1;
        var newline = false;
        while (j < raw.length && _space.hasMatch(raw[j])) {
          if (raw[j] == '\n') newline = true;
          j++;
        }
        if (newline && j < raw.length && _word.hasMatch(raw[j]) && raw[j] == raw[j].toLowerCase()) {
          i = j;
          continue;
        }
      }
      out.write(ch);
      source.add(rawSource[i]);
      i++;
      continue;
    }
    // A run of whitespace becomes one space, or a paragraph break if it
    // holds a blank line.
    final runStart = i;
    final runSource = rawSource[i];
    var newlines = 0;
    while (i < raw.length && _space.hasMatch(raw[i])) {
      if (raw[i] == '\n') newlines++;
      i++;
    }
    final lineLength = raw.substring(lineStart, runStart).trim().length;
    if (newlines > 0) lineStart = raw.lastIndexOf('\n', i - 1) + 1;
    if (out.isEmpty || i >= raw.length) continue;
    var paragraph = newlines >= 2 || (newlines == 1 && lineLength < shortLine);
    if (paragraph && newlines >= 2 && !_endsSentence(raw, runStart) && _startsLower(raw, i)) {
      paragraph = false;
    }
    final sep = paragraph ? '\n\n' : ' ';
    out.write(sep);
    source.addAll(List.filled(sep.length, runSource));
  }
  return (out.toString(), Int32List.fromList(source));
}

/// A "full" line's length: most lines of wrapped text are about this long.
/// Zero when there are too few lines to tell.
double _typicalLineLength(String raw) {
  final lengths = [
    for (final line in raw.split('\n'))
      if (line.trim().isNotEmpty) line.trim().length
  ]..sort();
  if (lengths.length < 5) return 0;
  return lengths[(lengths.length * 0.8).floor()].toDouble();
}

bool _endsSentence(String raw, int end) {
  var j = end - 1;
  while (j >= 0 && '"\'”’)]'.contains(raw[j])) {
    j--;
  }
  return j >= 0 && '.!?…:'.contains(raw[j]);
}

bool _startsLower(String raw, int i) {
  final ch = raw[i];
  return ch != ch.toUpperCase() && ch == ch.toLowerCase();
}

const _abbreviations = {
  'mr', 'mrs', 'ms', 'dr', 'prof', 'sr', 'jr', 'st', 'vs', 'etc', 'e.g', 'i.e',
  'fig', 'no', 'vol', 'p', 'pp', 'ch', 'cf', 'al', 'approx', 'inc', 'ltd', 'co',
};

final _sentenceEnd = RegExp(r'''[.!?…]+["'”’)\]]*(?=\s)''');

/// Splits [text] into sentences. Paragraph breaks always end a sentence, and
/// very long sentences are cut at a comma or space so speech engines that
/// stall on long utterances keep going.
List<Sentence> _splitSentences(String text, int maxLen) {
  final ends = <int>{};
  for (final m in _sentenceEnd.allMatches(text)) {
    if (text[m.start] == '.') {
      final before = text.substring(0, m.start);
      final word = RegExp(r'([A-Za-z.]+)$').firstMatch(before)?.group(1)?.toLowerCase();
      if (word != null && (_abbreviations.contains(word) || RegExp(r'^[a-z]$').hasMatch(word))) {
        continue;
      }
    }
    ends.add(m.end);
  }
  var p = text.indexOf('\n\n');
  while (p != -1) {
    ends.add(p);
    p = text.indexOf('\n\n', p + 2);
  }
  ends.add(text.length);

  final sentences = <Sentence>[];
  var start = 0;
  for (final end in ends.toList()..sort()) {
    var s = start;
    while (s < end && _space.hasMatch(text[s])) {
      s++;
    }
    while (end - s > maxLen) {
      final window = text.substring(s, s + maxLen);
      var cut = window.lastIndexOf(RegExp(r'[,;:]\s'));
      cut = cut > maxLen ~/ 3 ? cut + 1 : window.lastIndexOf(' ');
      if (cut <= 0) cut = maxLen;
      sentences.add(Sentence(s, s + cut));
      s += cut;
      while (s < end && _space.hasMatch(text[s])) {
        s++;
      }
    }
    if (s < end) sentences.add(Sentence(s, end));
    start = end;
  }
  return sentences;
}

/// Groups sentences into on-screen blocks: one per paragraph, with long
/// paragraphs split so no single block is huge.
List<Block> _groupBlocks(String text, List<Sentence> sentences, int maxLen) {
  final blocks = <Block>[];
  var first = 0;
  for (var i = 0; i < sentences.length; i++) {
    final last = i == sentences.length - 1;
    final next = last ? text.length : sentences[i + 1].start;
    final paragraphEnd = last || text.substring(sentences[i].end, next).contains('\n\n');
    final long = sentences[i].end - sentences[first].start >= maxLen;
    if (paragraphEnd || long) {
      blocks.add(Block(first, i, paragraphEnd: paragraphEnd));
      first = i + 1;
    }
  }
  return blocks;
}
