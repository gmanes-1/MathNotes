# MaLiang Fineliner prototype

This is an isolated integration experiment for MathNotes. The app's production PageStack,
PencilKit drawing storage, zoom canvas, undo routing, and export pipeline are unchanged.

## Why MaLiang

MaLiang exposes Brush.forceSensitive (0...1). Its width calculation is
pointSize * pow(force, forceSensitive), so a small exponent produces a much
softer pressure response than PencilKit's fixed native Pen curve.

The prototype defaults are intentionally conservative:
- base width: 0.65 points
- pressure sensitivity: 0.12
- brush opacity: 0.65
- Apple Pencil-only input

These are starting values for physical iPad testing, not claims about the final
appearance on every display.

## Using the prototype view

Instantiate MaLiangFinelinerPrototypeView in a temporary test screen. Call
configure(width:color:pressureSensitivity:) to compare widths and pressure
curves. The view also exposes snapshot(), undo(), redo(), clear(), and
saveVectorDocument(to:completion:).

MaLiang stores its own CanvasData/LineStrip vector document. It does not
currently convert to MathNotes' PKDrawing format. Do not connect it to normal
notebook pages until stroke conversion, replay, erasing/selection, zoom,
undo, persistence, and PDF export have been implemented and tested.

## Upstream

- Project: https://github.com/Harley-xk/MaLiang
- Upstream version: 2.9.2 source line (vendored from the repository's master branch)
- License: MIT (see LICENSE)

Utils.swift resource lookup is adapted for Swift Package Manager so the
Metal shader library is loaded from Bundle.module.
