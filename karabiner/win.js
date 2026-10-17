#!/usr/bin/osascript -l JavaScript
// Resize the frontmost window on the screen it's on. Called from gen.py binds.
//   win.js maximize   cover the whole screen (minus menu bar and Dock)
//   win.js almost     90% of the screen, centered, floating
ObjC.import("AppKit");

const ALMOST = 0.9;

function run(argv) {
  const mode = argv[0];
  const proc = Application("System Events").processes.whose({ frontmost: true })[0];
  const win = proc.windows[0];
  const [wx, wy] = win.position();
  const [ww, wh] = win.size();

  // NSScreen frames start at the bottom-left of the primary screen,
  // System Events positions at its top-left.
  const screens = $.NSScreen.screens;
  const primaryH = screens.objectAtIndex(0).frame.size.height;
  const cx = wx + ww / 2;
  const cy = primaryH - (wy + wh / 2);
  let vis = screens.objectAtIndex(0).visibleFrame;
  for (let i = 0; i < screens.count; i++) {
    const s = screens.objectAtIndex(i);
    const f = s.frame;
    if (cx >= f.origin.x && cx < f.origin.x + f.size.width &&
        cy >= f.origin.y && cy < f.origin.y + f.size.height) {
      vis = s.visibleFrame;
      break;
    }
  }

  let x = vis.origin.x;
  let w = vis.size.width;
  let h = vis.size.height;
  let y = primaryH - (vis.origin.y + h);
  if (mode === "almost") {
    x += (w * (1 - ALMOST)) / 2;
    y += (h * (1 - ALMOST)) / 2;
    w *= ALMOST;
    h *= ALMOST;
  } else if (mode !== "maximize") {
    throw new Error(`unknown mode ${mode}`);
  }

  // size, move, size again: some apps clamp the size to the old position
  win.size = [Math.round(w), Math.round(h)];
  win.position = [Math.round(x), Math.round(y)];
  win.size = [Math.round(w), Math.round(h)];
}
