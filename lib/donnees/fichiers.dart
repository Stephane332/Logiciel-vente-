/// Écriture et lecture des fichiers de sauvegarde sur l'appareil.
///
/// Séparé par plateforme comme l'ouverture de la base : le natif écrit dans
/// le dossier de l'application et passe par le partage du système, le web se
/// contente de télécharger. Le reste du code ne connaît que cette interface.
library;

export 'fichiers_native.dart'
    if (dart.library.js_interop) 'fichiers_web.dart';
