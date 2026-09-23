[![English](https://img.shields.io/badge/lang-English-lightgrey.svg)](README.md) [![Français](https://img.shields.io/badge/lang-Fran%C3%A7ais-F65801.svg)](README.fr.md)

# Tracer

Vectorise des logos, pictos et illustrations en aplats : une image bitmap en entrée,
un SVG propre en sortie — peu de nœuds, vrais cercles, vraies droites, dégradés conservés.

App macOS native (SwiftUI), sans dépendance externe.

## Ce qu'elle fait

- **Calques de couleur** — l'image est découpée en couleurs (k-means dans l'espace Lab).
  Les bandes d'un même dégradé sont détectées et regroupées : on peut demander plus de
  couleurs que nécessaire sans morceler un dégradé.
- **Contours sub-pixel** — chaque bord est placé d'après la couverture réelle du pixel
  (sa couleur mélangée, ou son alpha), pas au pixel près.
- **Courbes essentialisées** — lignes droites détectées, cercles exacts (4 Béziers),
  angles francs reconstruits, le reste ajusté par l'algorithme de Schneider sous une
  tolérance que tu règles.
- **Dégradés** — chaque calque reçoit un aplat ou un dégradé linéaire ajusté sur ses pixels.
- **Calques empilés** — une forme passe sous celles posées dessus : pas de liseré entre deux
  couleurs, pas de trou inutile (un disque reste un disque sous sa lettre).
- **Contrôle** — vue Original / Vecteur / Contours (tracés et points d'ancrage sur
  l'original) / Écart (carte de la différence), avec l'écart moyen chiffré.
- **Exports** — SVG, PNG 1024 à 4096 px, et jeu de favicons complet
  (`favicon.ico` 16/32/48, PNG, `apple-touch-icon`, icônes 192/512 et *maskable*,
  `site.webmanifest`).

## Installer

### Télécharger

Prends `Tracer-x.y.z.zip` dans les [Releases](https://github.com/Djoko-cli/tracer/releases),
décompresse-le et glisse `Tracer.app` dans Applications. macOS 14 ou plus récent,
Apple Silicon ou Intel.

L'app n'est pas notariée par Apple : au premier lancement, macOS la bloque. Ouvre
**Réglages Système › Confidentialité et sécurité** et clique sur **Ouvrir quand même**
(ou, dans le Terminal : `xattr -dr com.apple.quarantine /Applications/Tracer.app`).

### Compiler

Il faut Xcode (ou les Command Line Tools avec Swift 6) et macOS 14 ou plus récent.

```bash
./scripts/build-app.sh            # construit et installe ~/Applications/Tracer.app
./scripts/build-app.sh /Applications
UNIVERSAL=1 ./scripts/build-app.sh  # binaire Apple Silicon + Intel
```

Le dossier de compilation est placé dans `~/Library/Caches/TracerBuild` : quand le Bureau ou
Documents sont synchronisés avec iCloud, `codesign` refuse les attributs ajoutés par iCloud.

## Utiliser

1. Glisse une image dans la fenêtre (ou ⌘O, ou « Ouvrir avec… » depuis le Finder).
2. Règle **Couleurs** et **Précision** : le résultat se recalcule en direct.
3. Masque un calque avec l'œil (le fond blanc, typiquement) — le choix est gardé quand
   tu changes les réglages.
4. Exporte : ⌘E pour le SVG, ⇧⌘E pour les favicons, ou le menu Exporter.

## Limites connues

Tracer vise les images en aplats et dégradés linéaires. Il ne modélise pas les ombrages
complexes (plis, ombres portées, textures) : ils sont approchés par un dégradé linéaire.
Les très petits détails (moins de 3 px) sont absorbés par la couleur voisine.

## Ligne de commande

```bash
swift run --scratch-path ~/Library/Caches/TracerBuild -c release tracer-cli logo.png -o logo.svg --colors 8 --precision 1
```

## Structure

| Dossier | Contenu |
|---|---|
| `Sources/TracerCore` | le moteur : segmentation, tracé des contours, ajustement de courbes, dégradés, rendu, exports |
| `Sources/Tracer` | l'app SwiftUI |
| `Sources/tracer-cli` | la même chose en ligne de commande |
| `Tests/TracerCoreTests` | tests (Swift Testing) : `swift test --scratch-path ~/Library/Caches/TracerBuild` |

## Licence

MIT — voir [LICENSE](LICENSE).
