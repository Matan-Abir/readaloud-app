import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../api.dart';
import '../natural_speaker.dart';
import '../reader_controller.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.api, required this.doc, this.speaker});

  final ApiClient api;
  final DocumentInfo doc;
  final Speaker? speaker;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final Speaker _deviceVoice = DeviceSpeaker();
  late final ReaderController _reader = ReaderController(
    api: widget.api,
    doc: widget.doc,
    speaker: widget.speaker ?? _deviceVoice,
  )..init();
  late final VoiceChoice _voice = VoiceChoice(_reader);

  @override
  void initState() {
    super.initState();
    // Default to the natural (Piper) voice when the server offers it.
    if (widget.speaker == null) _voice.detect(widget.api, _deviceVoice);
  }

  @override
  void dispose() {
    _voice.dispose();
    _reader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.doc.title, overflow: TextOverflow.ellipsis),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.headphones), text: 'Listen'),
            Tab(icon: Icon(Icons.summarize), text: 'Summary'),
            Tab(icon: Icon(Icons.question_answer), text: 'Ask'),
          ]),
        ),
        body: TabBarView(children: [
          _ListenTab(reader: _reader, voice: _voice),
          _SummaryTab(api: widget.api, doc: widget.doc),
          _AskTab(api: widget.api, doc: widget.doc),
        ]),
      ),
    );
  }
}

/// Natural (server, Piper) vs device voice for the Listen tab.
class VoiceChoice extends ChangeNotifier {
  VoiceChoice(this.reader);

  final ReaderController reader;
  Speaker? _natural;
  Speaker? _device;
  String? voiceName;
  bool natural = false;
  bool fellBack = false;

  bool _disposed = false;

  bool get available => _natural != null;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> detect(ApiClient api, Speaker device) async {
    _device = device;
    try {
      final status = await api.ttsStatus();
      if (!status.available) return;
      voiceName = status.voice;
    } on ApiException {
      return;
    }
    if (_disposed) return;
    _natural = FallbackSpeaker(
      primary: NaturalSpeaker(synthesize: (text, speed) => api.synthesize(text, speed: speed)),
      secondary: device,
      onFallback: () {
        fellBack = true;
        notifyListeners();
      },
    );
    await setNatural(true);
  }

  Future<void> setNatural(bool on) async {
    final next = on ? _natural : _device;
    if (next == null) return;
    natural = on;
    notifyListeners();
    await reader.useSpeaker(next);
  }
}

class _ListenTab extends StatelessWidget {
  _ListenTab({required this.reader, required this.voice});

  final ReaderController reader;
  final VoiceChoice voice;
  final _textKey = GlobalKey();

  /// Map a tap on the displayed text to a character index and read from there.
  void _onTextTap(TapUpDetails details) {
    final paragraph = _textKey.currentContext?.findRenderObject();
    if (paragraph is! RenderParagraph) return;
    final position = paragraph.getPositionForOffset(paragraph.globalToLocal(details.globalPosition));
    reader.playFromCurrentText(position.offset);
  }

  static const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([reader, voice]),
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                // Full width, so the card doesn't shrink around short text.
                child: SizedBox(
                  width: double.infinity,
                  child: Card(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: reader.finished || reader.currentText.isEmpty
                          ? Text(
                              reader.finished ? 'Finished. Press play to start over.' : 'Press play to start listening.',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
                            )
                          : MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTapUp: _onTextTap,
                                child: Text(
                                  reader.currentText,
                                  key: _textKey,
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              if (reader.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(reader.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              if (reader.currentText.isNotEmpty && !reader.finished)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Tap any word to read from there.', style: Theme.of(context).textTheme.bodySmall),
                ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: reader.progress),
              const SizedBox(height: 4),
              Text('${(reader.progress * 100).round()}%'),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 32,
                    tooltip: 'Back',
                    icon: const Icon(Icons.replay_10),
                    onPressed: () => reader.seek(-1500),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    iconSize: 48,
                    tooltip: reader.playing ? 'Pause' : 'Play',
                    icon: Icon(reader.playing ? Icons.pause : Icons.play_arrow),
                    onPressed: reader.playing ? reader.pause : reader.play,
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    iconSize: 32,
                    tooltip: 'Forward',
                    icon: const Icon(Icons.forward_10),
                    onPressed: () => reader.seek(1500),
                  ),
                ],
              ),
              if (voice.available)
                SwitchListTile(
                  dense: true,
                  title: const Text('Natural voice'),
                  subtitle: Text(voice.fellBack
                      ? 'Unavailable right now, using the device voice'
                      : voice.natural
                          ? 'Piper · ${voice.voiceName ?? 'server voice'}'
                          : 'Using the device voice'),
                  value: voice.natural && !voice.fellBack,
                  onChanged: voice.fellBack ? null : voice.setNatural,
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
      },
    );
  }
}

class _SummaryTab extends StatefulWidget {
  const _SummaryTab({required this.api, required this.doc});

  final ApiClient api;
  final DocumentInfo doc;

  @override
  State<_SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends State<_SummaryTab> with AutomaticKeepAliveClientMixin {
  String? _summary;
  String? _error;
  bool _loading = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.api.summarize(widget.doc.id);
      if (mounted) setState(() => _summary = s);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_summary != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(_summary!, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5)),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.auto_awesome),
            label: Text(_error == null ? 'Summarize with AI' : 'Try again'),
          ),
        ],
      ),
    );
  }
}

class _AskTab extends StatefulWidget {
  const _AskTab({required this.api, required this.doc});

  final ApiClient api;
  final DocumentInfo doc;

  @override
  State<_AskTab> createState() => _AskTabState();
}

class _AskTabState extends State<_AskTab> with AutomaticKeepAliveClientMixin {
  final _controller = TextEditingController();
  final List<QaEntry> _entries = [];
  bool _asking = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.api.history(widget.doc.id).then((h) {
      if (mounted) setState(() => _entries.addAll(h));
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final q = _controller.text.trim();
    if (q.isEmpty || _asking) return;
    setState(() {
      _asking = true;
      _error = null;
    });
    try {
      final entry = await widget.api.ask(widget.doc.id, q);
      if (!mounted) return;
      setState(() {
        _entries.add(entry);
        _controller.clear();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Expanded(
          child: _entries.isEmpty
              ? const Center(child: Text('Ask anything about this document.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _entries.length,
                  itemBuilder: (_, i) {
                    final e = _entries[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.question, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        SelectableText(e.answer),
                        const Divider(height: 24),
                      ],
                    );
                  },
                ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _ask(),
                    decoration: const InputDecoration(
                      hintText: 'Ask a question…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _asking
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton.filled(onPressed: _ask, icon: const Icon(Icons.send)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
