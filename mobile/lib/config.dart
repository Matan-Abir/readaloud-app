/// Backend base URL. Override per build:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
/// Default 10.0.2.2 is the host machine as seen from the Android emulator.
/// `same-origin` (used by the web image behind nginx and the Ingress) means the
/// server the web page itself was loaded from.
const String _apiBaseUrlDefine =
    String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');

String get apiBaseUrl =>
    _apiBaseUrlDefine == 'same-origin' ? Uri.base.origin : _apiBaseUrlDefine;
