# Clairière

[![Open source, libre complet](https://img.shields.io/badge/open%20source-libre%20complet-2F7D46?style=for-the-badge)](LICENSE)
[![Licence MIT](https://img.shields.io/badge/licence-MIT-brightgreen?style=for-the-badge)](LICENSE)
[![macOS 14 ou plus](https://img.shields.io/badge/macOS-14%2B-111210?style=for-the-badge)](https://github.com/JSurquin/Clairiere/releases)

Clairière te montre quelle app tient la mémoire, et ce qui encombre le disque. Fermer Chrome rend de la mémoire. Ça ne vide pas le disque. Un vieux `.dmg` dans Téléchargements, c’est l’inverse.

Tu vois la liste, tu coches, tu confirmes. Ensuite ça va à la Corbeille, et tu peux le reprendre.

[Télécharger Clairière](https://github.com/JSurquin/Clairiere/releases) pour un Mac Apple silicon, macOS 14 ou plus récent. Le code est sous [licence MIT](LICENSE).

## À l’écran

L’accueil donne les gros chiffres. Le reste attend que tu ouvres l’onglet.

<img src="docs/screenshots/accueil.png" alt="Accueil de Clairière" width="860">

Chaque app a sa ligne. Fermer lui demande de partir. Forcer l’enlève, icône de la barre comprise.

<img src="docs/screenshots/memoire.png" alt="Onglet Mémoire" width="860">

Caches fait 7 Go chez moi. La petite flèche ouvre la liste des dossiers, du plus lourd au plus léger.

<img src="docs/screenshots/nettoyage.png" alt="Onglet Nettoyage" width="860">

Le disque, et les fichiers iCloud qui ont encore une copie sur ce Mac.

<img src="docs/screenshots/stockage.png" alt="Onglet Stockage" width="860">

## Dedans

La mémoire est rangée en navigateurs, apps ouvertes, arrière-plan et macOS. Tu peux aussi trier par taille, ou voir ce qui augmente.

Le nettoyage propose les caches, les journaux et la corbeille. Les images disque dans Téléchargements restent décochées. Tu les as peut-être gardées.

Dans Stockage, retirer un fichier iCloud n’enlève que la copie locale. Il reste dans iCloud et revient quand tu l’ouvres.

Apps donne la taille, les fichiers laissés par une app désinstallée, et une remise à zéro des préférences. Démarrage liste ce qui s’ouvre avec le Mac. Tu peux le couper, puis le remettre.

L’onglet IA regarde les fichiers pas ouverts depuis trois mois. Il se sert du nom, de la date et de la taille. Il n’ouvre pas le fichier. Si tu lances une analyse, [Ollama](https://ollama.com) s’installe tout seul, tourne sur le Mac, puis se ferme.

L’accueil ne lance pas ces lectures tout seul. Le thème sombre est celui du départ. Clair est juste en dessous du nom.

Vider la corbeille du Mac, ou supprimer un instantané Time Machine, est marqué comme définitif. Finder et le Dock restent sur « laisser ouvert ».

Ce n’est pas un antivirus. Les permissions restent celles de macOS.

## Installer

Le zip s’appelle `Clairiere-macOS.zip`, sur [Releases](https://github.com/JSurquin/Clairiere/releases).

1. Ouvre l’archive.
2. Glisse Clairière dans Applications.
3. Au premier lancement, clic droit sur l’app, puis Ouvrir.

Apple n’a pas notarié cette build. macOS pose la question une fois.

## Compiler

Il te faut macOS 14 et Swift 6. Xcode peut rester fermé.

```bash
git clone https://github.com/JSurquin/Clairiere.git
cd Clairiere
./build.sh
open dist/Clairiere.app
```

`./build.sh` compile l’app et la pose dans `dist/`.

## Publier une version

Dans l’onglet [Actions](https://github.com/JSurquin/Clairiere/actions), ouvre **Release**, puis **Run workflow**, et mets un numéro du genre `1.2.3`.

Tu peux aussi pousser le tag toi-même.

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
| ⌘A / ⌘⇧A | Tout cocher / tout décocher |
| ⌘Retour | Action de la ligne |
| ⌘⇧Retour | Forcer la fermeture |
| ⌘O | Montrer dans le Finder |
| ⌘L | Libérer de la mémoire |
| Échap | Ferme le dialogue, le détail, puis la recherche |

## Licence

[MIT](LICENSE). Tu peux t’en servir, le modifier, le redistribuer.
