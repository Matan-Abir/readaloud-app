import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readaloud/api.dart';
import 'package:readaloud/screens/reader_screen.dart';

import 'reader_controller_test.dart' show HoldingSpeaker;

void main() {
  testWidgets('tapping a word in Listen reads from that word', (tester) async {
    const text = 'Alpha beta gamma.';
    final starts = <int>[];
    final api = ApiClient(
      baseUrl: 'http://x',
      client: MockClient((req) async {
        if (req.url.path.endsWith('/chunks')) {
          final start = int.parse(req.url.queryParameters['start'] ?? '0');
          starts.add(start);
          final chunks = start < text.length ? [{'offset': start, 'text': text.substring(start)}] : [];
          return http.Response(jsonEncode({'chunks': chunks, 'text_length': text.length}), 200);
        }
        return http.Response('{}', 200);
      }),
    );
    final speaker = HoldingSpeaker();
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        api: api,
        doc: DocumentInfo(id: 1, title: 't', pageCount: 1, textLength: text.length, progressChar: 0),
        speaker: speaker,
      ),
    ));

    await tester.tap(find.byTooltip('Play'));
    await tester.pumpAndSettle();
    expect(find.text(text), findsOneWidget);
    expect(find.text('Tap any word to read from there.'), findsOneWidget);

    // Tap near the right edge of the text, inside "gamma".
    final rect = tester.getRect(find.text(text));
    await tester.tapAt(Offset(rect.right - 4, rect.center.dy));
    await tester.pumpAndSettle();

    expect(starts.last, text.indexOf('gamma'));
    expect(speaker.spoken.last, 'gamma.');
    expect(find.byTooltip('Pause'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
  });
}
