// Lets the web build offer "Install app". On phones and desktops apps this does nothing.
export 'pwa_install_stub.dart' if (dart.library.html) 'pwa_install_web.dart';
