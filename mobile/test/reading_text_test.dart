import 'package:flutter_test/flutter_test.dart';
import 'package:readaloud/api.dart';
import 'package:readaloud/reading_text.dart';

ReadingText build(String raw) => ReadingText.fromChunks([TextChunk(0, raw)]);

List<String> sentences(ReadingText t) =>
    [for (var i = 0; i < t.sentences.length; i++) t.sentenceText(i)];

void main() {
  test('joins wrapped lines into one flowing line', () {
    final t = build('The quick brown\nfox jumps over\n  the lazy dog.');
    expect(t.text, 'The quick brown fox jumps over the lazy dog.');
    expect(sentences(t), ['The quick brown fox jumps over the lazy dog.']);
  });

  test('rejoins words hyphenated across a line wrap', () {
    expect(build('an exam-\nple of it').text, 'an example of it');
    expect(build('well-known').text, 'well-known');
  });

  test('keeps blank lines as paragraph breaks', () {
    final t = build('First line\nstill first.\n\nSecond paragraph');
    expect(t.text, 'First line still first.\n\nSecond paragraph');
    expect(sentences(t), ['First line still first.', 'Second paragraph']);
    expect(t.blocks.length, 2);
    expect(t.blocks.first.paragraphEnd, isTrue);
  });

  test('splits sentences but not common abbreviations', () {
    final t = build('Dr. Smith arrived. Was he late? Yes! See e.g. page 4.');
    expect(sentences(t), ['Dr. Smith arrived.', 'Was he late?', 'Yes!', 'See e.g. page 4.']);
  });

  test('cuts very long sentences at a comma or space', () {
    final long = List.filled(40, 'word').join(' ');
    final t = ReadingText.fromChunks([TextChunk(0, '$long, $long.')], maxSentence: 250);
    expect(t.sentences.length, greaterThan(1));
    for (final s in t.sentences) {
      expect(s.end - s.start, lessThanOrEqualTo(250));
    }
    expect(sentences(t).join(' '), '$long, $long.');
  });

  test('glues server chunks and maps back to server offsets', () {
    // Server text: "One two.\nThree four.\n\nFive." split into chunks.
    final t = ReadingText.fromChunks([
      TextChunk(0, 'One two.\nThree four.'),
      TextChunk(22, 'Five.'),
    ]);
    expect(t.text, 'One two. Three four.\n\nFive.');
    expect(sentences(t), ['One two.', 'Three four.', 'Five.']);
    expect(t.sourceOffset(t.sentences[1].start), 9);
    expect(t.sourceOffset(t.sentences[2].start), 22);
    expect(t.sentenceAtSource(0), 0);
    expect(t.sentenceAtSource(12), 1);
    expect(t.sentenceAtSource(25), 2);
  });

  test('a short line ends a paragraph even without a blank line (PDF text)', () {
    const raw = 'Chapter 1\n'
        'Continuous integration is the practice of merging every\n'
        'developer change into a shared branch several times a day\n'
        'so that problems surface early, within minutes of the push.\n'
        'That is all.\n'
        'A good pipeline is fast, repeatable and boring. It checks out\n'
        'the code, installs dependencies and runs the tests every time.';
    final t = build(raw);
    final paragraphs = t.text.split('\n\n');
    expect(paragraphs.length, 3);
    expect(paragraphs[0], 'Chapter 1');
    expect(paragraphs[1], startsWith('Continuous integration is the practice of merging every developer'));
    expect(paragraphs[1], endsWith('within minutes of the push. That is all.'));
    expect(paragraphs[2], startsWith('A good pipeline'));
  });

  test('a page break in the middle of a sentence is joined', () {
    final t = build('This sentence runs onto\n\nthe next page. New one.');
    expect(t.text, 'This sentence runs onto the next page. New one.');
  });
}
