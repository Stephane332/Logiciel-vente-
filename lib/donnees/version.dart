/// La version de l'application, écrite une fois et lue partout.
///
/// Elle s'affiche dans les réglages et voyage dans chaque sauvegarde. Sans
/// elle, le jour où un commerçant m'appellera pour un chiffre faux, je ne
/// saurai pas ce qu'il a installé — et la moitié du dépannage consiste à le
/// savoir.
///
/// Elle est aussi ce que le comité d'homologation demandera : un SFE
/// s'identifie par son modèle et sa version.
library;

/// Numéro de version, aligné sur celui du `pubspec.yaml`.
const versionApplication = '0.8.1';

/// Nom du modèle, tel qu'il apparaîtra au dossier d'homologation.
const nomApplication = 'Carnet';

/// Ce qui s'affiche en pied de réglages.
const empreinteVersion = '$nomApplication $versionApplication';
