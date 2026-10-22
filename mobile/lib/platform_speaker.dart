import 'api.dart';
import 'reader_controller.dart';

/// On phones (and anywhere but the web) the flutter_tts engine is used.
Speaker createPlatformSpeaker(ApiClient api) => DeviceSpeaker();
