/// Backend base URL. Override per build:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
/// Default 10.0.2.2 is the host machine as seen from the Android emulator.
const String apiBaseUrl =
    String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');
