# CHIZEL

CHIZEL is a Godot 4 prototype for carving low-poly models from block-like primitives into connected flat shell meshes.

## Current Milestone

This build targets the first blueprint milestone:

- Starts with a cube backed by a hidden carving grid.
- Shows a rotatable perspective preview.
- Provides locked Front, Back, Left, Right, Top, and Bottom orthographic modelling views.
- Draws a modelling grid in orthographic views.
- Imports a transparent reference image layer for tracing in orthographic views.
- Supports a Chisel polygon lasso.
- Projects the lasso through the model to add or remove selected material.
- Rebuilds the visible model as a stable solid-looking shell after every carve.
- Supports Undo, Redo, and Reset Model.
- Exports the current shell as `.glb`.

## Controls

- Left mouse drag: orbit in perspective view.
- Mouse wheel: zoom in perspective view.
- Middle mouse drag: pan in perspective view.
- Mirror X: repeats Chisel cuts across the model centre.
- Add/Subtract: chooses whether the Chisel lasso fills material or removes it.
- Clean Solid: removes loose fragments and thin shards so the perspective view stays readable.
- Import Ref: loads a 2D image into the active blueprint workspace for tracing.
- Show Ref, Opacity, Scale, nudges, Center Ref, and Clear Ref: align the reference image.
- Export GLB: saves the current connected shell model for use elsewhere.
- Chisel mode: click to place lasso points.
- Enter: apply the lasso operation.
- Click the first point: close and apply the lasso operation.
- Backspace: remove the last lasso point.
- Escape: cancel the current lasso.
- Ctrl + Z: undo.
- Ctrl + Y or Ctrl + Shift + Z: redo.

## GitHub Pages Deployment

This repo includes a GitHub Pages app shell, a Godot Web export preset, and a deploy workflow. The public page is meant to open the CHIZEL Godot build directly, not show the README.

1. Push the project to a GitHub repo.
2. In GitHub, open Settings -> Pages.
3. Set Build and deployment to GitHub Actions.
4. Run the `Deploy CHIZEL to GitHub Pages` workflow, or push to `main`/`master`.

The workflow exports the Godot Web preset to `docs/game/CHIZEL.html`, then publishes the full `docs/` folder as the Pages site.

If GitHub Pages is set to deploy from the branch root instead of GitHub Actions, `index.html` will still load the same exported Godot build from `docs/game/CHIZEL.html`.

For a manual local export, open Godot and export the `Web` preset. The target path is:

```text
docs/game/CHIZEL.html
```
