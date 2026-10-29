import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../reader_controller.dart';
import '../reading_text.dart';

/// The whole document as one scrolling page. The sentence being read is
/// highlighted and kept in view; tapping a sentence starts reading there.
class ListenTab extends StatefulWidget {
  const ListenTab({super.key, required this.reader});

  final ReaderController reader;

  @override
  State<ListenTab> createState() => _ListenTabState();
}

class _ListenTabState extends State<ListenTab> with AutomaticKeepAliveClientMixin {
  static const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  final _scroll = ScrollController();
  ReadingText? _content;
  List<GlobalKey> _keys = const [];
  List<Widget> _blocks = const [];
  int _highlightBlock = -1;
  int _highlightSentence = -1;
  TextStyle? _style;
  ColorScheme? _colors;

  ReaderController get reader => widget.reader;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    reader.addListener(_onReaderChanged);
  }

  @override
  void dispose() {
    reader.removeListener(_onReaderChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onReaderChanged() {
    if (!mounted) return;
    final moved = reader.content != null && reader.current != _highlightSentence;
    setState(() {});
    if (moved) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  int _blockOf(int sentence) {
    final blocks = _content!.blocks;
    var lo = 0, hi = blocks.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (blocks[mid].first <= sentence) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  Widget _buildBlock(int b, int highlight) {
    final content = _content!;
    return _BlockText(
      textKey: _keys[b],
      content: content,
      block: content.blocks[b],
      highlight: highlight,
      style: _style!,
      highlightColor: _colors!.primaryContainer,
      onTap: reader.playFrom,
    );
  }

  /// Rebuilds only the blocks whose highlight changed, so long documents stay
  /// fast while reading.
  void _syncBlocks(BuildContext context) {
    final content = reader.content!;
    final style = Theme.of(context).textTheme.bodyLarge!.copyWith(height: 1.6);
    final colors = Theme.of(context).colorScheme;
    final current = content.sentences.isEmpty ? -1 : reader.current;
    if (!identical(content, _content) || style != _style || colors != _colors) {
      _content = content;
      _style = style;
      _colors = colors;
      _keys = [for (var i = 0; i < content.blocks.length; i++) GlobalKey()];
      _highlightSentence = current;
      _highlightBlock = current < 0 ? -1 : _blockOf(current);
      _blocks = [
        for (var b = 0; b < content.blocks.length; b++)
          _buildBlock(b, b == _highlightBlock ? current : -1),
      ];
      return;
    }
    if (current == _highlightSentence) return;
    final block = current < 0 ? -1 : _blockOf(current);
    _blocks = List.of(_blocks);
    if (_highlightBlock >= 0) _blocks[_highlightBlock] = _buildBlock(_highlightBlock, -1);
    if (block >= 0) _blocks[block] = _buildBlock(block, current);
    _highlightBlock = block;
    _highlightSentence = current;
  }

  /// Scrolls so the sentence being read sits near the top third of the page,
  /// but only when it is not already fully visible.
  void _scrollToCurrent() {
    if (!mounted || _highlightBlock < 0 || !_scroll.hasClients) return;
    final paragraph = _keys[_highlightBlock].currentContext?.findRenderObject();
    if (paragraph is! RenderParagraph) return;
    final content = _content!;
    final block = content.blocks[_highlightBlock];
    final base = content.sentences[block.first].start;
    final s = content.sentences[_highlightSentence];
    final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: s.start - base, extentOffset: s.end - base));
    if (boxes.isEmpty) return;
    var rect = boxes.first.toRect();
    for (final box in boxes.skip(1)) {
      rect = rect.expandToInclude(box.toRect());
    }
    final viewport = RenderAbstractViewport.maybeOf(paragraph);
    if (viewport == null) return;
    final position = _scroll.position;
    final top = viewport.getOffsetToReveal(paragraph, 0, rect: rect).offset;
    final y = top - position.pixels;
    if (y >= 0 && y + rect.height <= position.viewportDimension) return;
    final target = viewport.getOffsetToReveal(paragraph, 0.25, rect: rect).offset;
    _scroll.animateTo(target.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    Widget page;
    if (reader.content == null) {
      page = Center(
        child: reader.loading
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text('Loading text… ${(reader.loaded * 100).round()}%'),
              ])
            : FilledButton(onPressed: reader.load, child: const Text('Try again')),
      );
    } else if (reader.content!.sentences.isEmpty) {
      page = const Center(child: Text('This document has no readable text.'));
    } else {
      _syncBlocks(context);
      page = Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _blocks),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(child: SizedBox(width: double.infinity, child: Card(child: page))),
          if (reader.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(reader.error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: reader.progress),
          const SizedBox(height: 4),
          Text(reader.finished
              ? 'Finished. Press play to start over.'
              : '${(reader.progress * 100).round()}%  ·  Tap any sentence to read from there'),
          if (reader.voiceName != null)
            Text(reader.voiceName!, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 32,
                tooltip: 'Previous sentence',
                icon: const Icon(Icons.skip_previous),
                onPressed: () => reader.jumpTo(reader.current - 1),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                iconSize: 48,
                tooltip: reader.playing ? 'Pause' : 'Play',
                icon: Icon(reader.playing ? Icons.pause : Icons.play_arrow),
                onPressed: reader.content == null
                    ? null
                    : reader.playing
                        ? reader.pause
                        : reader.play,
              ),
              const SizedBox(width: 12),
              IconButton(
                iconSize: 32,
                tooltip: 'Next sentence',
                icon: const Icon(Icons.skip_next),
                onPressed: () => reader.jumpTo(reader.current + 1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<double>(
            showSelectedIcon: false,
            segments: [for (final s in _speeds) ButtonSegment(value: s, label: Text('${s}x'))],
            selected: {reader.speed},
            onSelectionChanged: (v) => reader.setSpeed(v.first),
          ),
        ],
      ),
    );
  }
}

/// One block of sentences. Each sentence is its own tappable span.
class _BlockText extends StatefulWidget {
  const _BlockText({
    required this.textKey,
    required this.content,
    required this.block,
    required this.highlight,
    required this.style,
    required this.highlightColor,
    required this.onTap,
  });

  final GlobalKey textKey;
  final ReadingText content;
  final Block block;
  final int highlight;
  final TextStyle style;
  final Color highlightColor;
  final void Function(int sentence) onTap;

  @override
  State<_BlockText> createState() => _BlockTextState();
}

class _BlockTextState extends State<_BlockText> {
  final List<TapGestureRecognizer> _taps = [];

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _tap(int index, int sentence) {
    while (_taps.length <= index) {
      _taps.add(TapGestureRecognizer());
    }
    return _taps[index]..onTap = () => widget.onTap(sentence);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.content;
    final b = widget.block;
    final spans = <InlineSpan>[];
    for (var i = b.first; i <= b.last; i++) {
      final s = c.sentences[i];
      spans.add(TextSpan(
        text: c.text.substring(s.start, s.end),
        recognizer: _tap(i - b.first, i),
        style: i == widget.highlight ? TextStyle(backgroundColor: widget.highlightColor) : null,
      ));
      if (i < b.last) spans.add(TextSpan(text: c.text.substring(s.end, c.sentences[i + 1].start)));
    }
    return Padding(
      padding: EdgeInsets.only(bottom: b.paragraphEnd ? 16 : 0),
      child: Text.rich(key: widget.textKey, TextSpan(style: widget.style, children: spans)),
    );
  }
}
