/// Not a browser: nothing to install.
class PwaInstall {
  PwaInstall._();

  /// True when the player is in a browser tab (not already opened from the home screen).
  static bool get canOffer => false;

  /// True on iPhone and iPad, where the browser has no install button to trigger.
  static bool get isIos => false;

  /// True when the browser can show its own install sheet.
  static bool get canPrompt => false;

  /// Shows the browser's install sheet. Returns true if the player accepted.
  static Future<bool> prompt() async => false;
}
