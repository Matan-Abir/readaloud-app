import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/documents_screen.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(ReadAloudApp(api: ApiClient()..loadToken()));
}

class ReadAloudApp extends StatelessWidget {
  const ReadAloudApp({super.key, required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ReadAloud',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: ListenableBuilder(
        listenable: api,
        builder: (context, _) =>
            api.loggedIn ? DocumentsScreen(api: api) : LoginScreen(api: api),
      ),
    );
  }
}
