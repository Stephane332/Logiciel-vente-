/// Ouverture de la base sur l'appareil.
///
/// L'implémentation dépend de la plateforme : SQLite natif sur Android et
/// iOS, SQLite compilé en WebAssembly dans le navigateur. Le choix se fait à
/// la compilation par import conditionnel, parce que le code natif importe
/// `dart:ffi`, qui n'existe pas sur le web.
///
/// La version web sert de démonstration : elle permet de montrer
/// l'application sans rien installer.
library;

export 'ouverture_native.dart'
    if (dart.library.js_interop) 'ouverture_web.dart';
