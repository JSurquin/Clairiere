# Clairière

[![Open source, libre complet](https://img.shields.io/badge/open%20source-libre%20complet-2F7D46?style=for-the-badge)](LICENSE)
[![Licence MIT](https://img.shields.io/badge/licence-MIT-brightgreen?style=for-the-badge)](LICENSE)
[![macOS 14 ou plus](https://img.shields.io/badge/macOS-14%2B-111210?style=for-the-badge)](https://github.com/JSurquin/Clairiere/releases)

Clairière répond à deux questions : qu’est-ce qui prend la mémoire de mon Mac, et qu’est-ce qui remplit son disque. Ce sont deux problèmes différents. Fermer une app libère de la mémoire, mais ça ne fait pas de place sur le disque. Pour le disque, il faut retirer des fichiers.

L’app te montre les deux, puis te laisse choisir quoi enlever. Rien ne part sans que tu l’aies coché et confirmé. Les fichiers vont à la Corbeille, donc tu peux encore les reprendre.

Elle fonctionne sur les Mac Apple silicon, avec macOS 14 ou plus récent. Le code est sous [licence MIT](LICENSE).

[Télécharger la dernière version](https://github.com/JSurquin/Clairiere/releases)

## Captures

L’accueil résume les chiffres sans lancer de gros calcul.

<img src="docs/screenshots/accueil.png" alt="Accueil de Clairière" width="860">

Chaque app a sa ligne. Fermer lui demande de s’arrêter. Forcer la ferme tout de suite, et enlève aussi son icône dans la barre de menus.

<img src="docs/screenshots/memoire.png" alt="Onglet Mémoire" width="860">

Dans Nettoyage, une ligne comme Caches peut peser plusieurs gigaoctets. Un clic sur la flèche montre les dossiers qu’elle contient, du plus lourd au plus léger.

<img src="docs/screenshots/nettoyage.png" alt="Onglet Nettoyage" width="860">

Stockage affiche la place libre sur le disque, et les fichiers iCloud qui ont encore une copie sur le Mac.

<img src="docs/screenshots/stockage.png" alt="Onglet Stockage" width="860">

## Les onglets

| Onglet | À quoi il sert |
| --- | --- |
| Accueil | Un résumé. Il ne lance aucun calcul lourd tout seul. |
| Mémoire | Les apps qui tournent, avec ce qu’elles utilisent. |
| Nettoyage | Les caches, les journaux et la corbeille du Mac. |
| Stockage | La place sur le disque, et les fichiers iCloud à retirer de ce Mac. |
| Apps | La taille de chaque app, les fichiers qu’elle laisse derrière elle, et les mises à jour. |
| Démarrage | Ce qui s’ouvre avec le Mac. On peut le couper, puis le remettre. |
| IA | Les vieux fichiers, triés avec un petit modèle installé sur le Mac. |

## Ce qui ne part jamais sans ton accord

Chaque suppression passe par une liste, puis une confirmation. La plupart des fichiers vont à la Corbeille. Vider la corbeille du Mac et supprimer un instantané Time Machine sont définitifs, et l’app le dit avant de les faire.

Retirer un fichier iCloud n’enlève que sa copie sur ce Mac. Le fichier reste dans iCloud et revient quand tu l’ouvres.

Le Finder, le Dock et les composants de macOS sont marqués « laisser ouvert ». Clairière ne les touche pas.

Clairière n’est pas un antivirus, et elle ne répare pas les permissions.

## L’onglet IA

L’onglet IA regarde les fichiers qui n’ont pas été ouverts depuis plus de trois mois. Il lit le nom, la date et la taille, mais n’ouvre jamais le contenu.

Quand tu lances l’analyse, Clairière installe [Ollama](https://ollama.com) s’il manque, charge un petit modèle, puis le décharge de la mémoire. Si Ollama tournait déjà avant, Clairière le laisse tranquille. Si c’est Clairière qui l’a lancé, elle le referme ensuite.

## Installer

1. Télécharge `Clairiere-macOS.zip` depuis [Releases](https://github.com/JSurquin/Clairiere/releases).
2. Ouvre l’archive, puis glisse Clairière dans le dossier Applications.
3. Au premier lancement, fais un clic droit sur l’app, puis choisis Ouvrir.

Cette version n’est pas notariée par Apple, donc macOS demande cette confirmation une seule fois.

## Compiler

Il faut macOS 14 et Swift 6. Xcode n’est pas nécessaire.

```bash
git clone https://github.com/JSurquin/Clairiere.git
cd Clairiere
./build.sh
open dist/Clairiere.app
```

Le script compile l’app et la place dans `dist/`.

## Publier une version

Dans l’onglet [Actions](https://github.com/JSurquin/Clairiere/actions), lance le workflow **Release** avec un numéro comme `1.2.3`. Il compile l’app et crée la release sur GitHub.

Tu peux aussi pousser un tag toi-même :

```bash
git tag v1.2.3
git push origin v1.2.3
```

## Clavier

| Raccourci | Action |
| --- | --- |
| ⌘1 à ⌘7 | Accueil, Mémoire, Nettoyage, Stockage, Apps, Démarrage, IA |
| ⌘F | Recherche |
| ↑ ↓ | Ligne précédente ou suivante |
| Entrée | Ouvre le détail |
| Espace | Coche ou décoche |
| ⌘A / ⌘⇧A | Tout cocher, tout décocher |
| ⌘Retour | Action de la ligne |
| ⌘⇧Retour | Forcer la fermeture |
| ⌘O | Montrer dans le Finder |
| ⌘L | Libérer de la mémoire |
| Échap | Ferme le dialogue, le détail, puis la recherche |

## Licence

Le code est sous [licence MIT](LICENSE). Tu peux l’utiliser, le modifier et le redistribuer, y compris dans un projet payant.
