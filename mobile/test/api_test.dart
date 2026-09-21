import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readaloud/api.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('login stores the token and sends it on later calls', () async {
    String? sentAuth;
    final api = ApiClient(
      baseUrl: 'http://x',
      client: MockClient((req) async {
        if (req.url.path == '/api/auth/login') {
          return http.Response(jsonEncode({'access_token': 'tok'}), 200);
        }
        sentAuth = req.headers['Authorization'];
        return http.Response('[]', 200);
      }),
    );
    await api.login('a@b.com', 'password123');
    expect(api.loggedIn, isTrue);
    await api.listDocuments();
    expect(sentAuth, 'Bearer tok');
    expect((await SharedPreferences.getInstance()).getString('access_token'), 'tok');
  });

  test('bad credentials surface the server message', () async {
    final api = ApiClient(
      baseUrl: 'http://x',
      client: MockClient((_) async => http.Response('{"error":"Invalid credentials"}', 401)),
    );
    expect(
      api.login('a@b.com', 'wrongpass1'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Invalid credentials')),
    );
    expect(api.loggedIn, isFalse);
  });

  test('a 401 on an authenticated call logs the user out', () async {
    SharedPreferences.setMockInitialValues({'access_token': 'expired'});
    final api = ApiClient(
      baseUrl: 'http://x',
      client: MockClient((_) async => http.Response('{"msg":"Token has expired"}', 401)),
    );
    await api.loadToken();
    expect(api.loggedIn, isTrue);
    await expectLater(api.listDocuments(), throwsA(isA<ApiException>()));
    await Future<void>.delayed(Duration.zero);
    expect(api.loggedIn, isFalse);
  });

  test('network failure becomes a friendly error', () async {
    final api = ApiClient(
      baseUrl: 'http://x',
      client: MockClient((_) async => throw http.ClientException('down')),
    );
    expect(
      api.listDocuments(),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Cannot reach'))),
    );
  });
}
