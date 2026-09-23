[![English](https://img.shields.io/badge/lang-English-F65801.svg)](README.md) [![Français](https://img.shields.io/badge/lang-Fran%C3%A7ais-lightgrey.svg)](README.fr.md)

# Tracer

Vectorizes logos, icons and flat-color illustrations: a bitmap image in, a clean SVG out —
few nodes, true circles, true straight lines, gradients preserved.

Native macOS app (SwiftUI), no external dependencies. The interface is in French.

## What it does

- **Color layers** — the image is split into colors (k-means in Lab space). Bands of the
  same gradient are detected and merged, so you can ask for more colors than needed
  without breaking a gradient apart.
- **Sub-pixel outlines** — every edge is placed from the pixel's actual coverage (its
  blended color, or its alpha), not snapped to the pixel grid.
- **Pared-down curves** — straight lines are detected, circles come out exact (4 Béziers),
  sharp corners are rebuilt, and the rest is fitted with Schneider's algorithm within a
  tolerance you set.
- **Gradients** — each layer gets a flat fill or a linear gradient fitted to its pixels.
- **Stacked layers** — a shape runs under whatever sits on top of it: no hairline gap
  between two colors, no needless hole (a disc stays a disc under its letter).
- **Checking** — four views, **Original**, **Vecteur** (vector), **Contours** (paths and
  anchor points over the original) and **Écart** (error map), with the mean error as a number.
- **Exports** — SVG, PNG from 1024 to 4096 px, and a complete favicon set
  (`favicon.ico` 16/32/48, PNGs, `apple-touch-icon`, 192/512 and *maskable* icons,
  `site.webmanifest`).

## Install

### Download

Get `Tracer-x.y.z.zip` from the [Releases](https://github.com/Djoko-cli/tracer/releases),
unzip it and drag `Tracer.app` into Applications. macOS 14 or later, Apple Silicon or Intel.

The app is not notarized by Apple, so macOS blocks it on first launch. Open
**System Settings › Privacy & Security** and click **Open Anyway**
(or, in Terminal: `xattr -dr com.apple.quarantine /Applications/Tracer.app`).

### Build

You need Xcode (or the Command Line Tools with Swift 6) and macOS 14 or later.

```bash
./scripts/build-app.sh            # builds and installs ~/Applications/Tracer.app
./scripts/build-app.sh /Applications
UNIVERSAL=1 ./scripts/build-app.sh  # Apple Silicon + Intel binary
```

The build folder lives in `~/Library/Caches/TracerBuild`: when the Desktop or Documents
folder is synced with iCloud, `codesign` rejects the attributes iCloud adds to files.

## Use

1. Drop an image into the window (or ⌘O, or "Open With…" in the Finder).
2. Adjust **Couleurs** (colors) and **Précision** (precision): the result updates live.
3. Hide a layer with the eye button (typically the white background) — the choice is kept
   when you change the settings.
4. Export: ⌘E for the SVG, ⇧⌘E for the favicons, or the **Exporter** menu.

## Known limitations

Tracer is built for flat colors and linear gradients. It does not model complex shading
(folds, drop shadows, textures): these are approximated with a linear gradient.
Very small details (under 3 px) are absorbed by the neighboring color.

## Command line

```bash
swift run --scratch-path ~/Library/Caches/TracerBuild -c release tracer-cli logo.png -o logo.svg --colors 8 --precision 1
```

## Layout

| Folder | Contents |
|---|---|
| `Sources/TracerCore` | the engine: segmentation, contour tracing, curve fitting, gradients, rendering, exports |
| `Sources/Tracer` | the SwiftUI app |
| `Sources/tracer-cli` | the same from the command line |
| `Tests/TracerCoreTests` | tests (Swift Testing): `swift test --scratch-path ~/Library/Caches/TracerBuild` |

## License

MIT — see [LICENSE](LICENSE).
