// Does this device have internet at all? Used to tell "you're offline" apart from "our service is down".
export 'reachability_io.dart' if (dart.library.html) 'reachability_web.dart';
