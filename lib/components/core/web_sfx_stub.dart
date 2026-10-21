/// Not the web: the phone builds use the normal audio player (see app_sound.dart).
class WebSfx {
  WebSfx._();
  static Future<void> preload(List<String> files) async {}
  static void play(String file, double volume) {}
}
