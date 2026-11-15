/*

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// Showcase scenes: what the page shows for the README. The preview plays them, and `npm run capture` saves each one
// to .github/assets/<id>.webp, animated when `animated` is set. Add a scene for every screen worth showing.

import { Kind, Layout, NuiAction, Reason, type NuiMessage, type TargetOption } from "@/types/protocol";

/** One step: a message as Lua would send it, or a click on an element, then a pause. */
export interface SceneStep {
  send?: NuiMessage;
  /** CSS selector of the element to click. */
  click?: string;
  /** Milliseconds before the next step. */
  wait?: number;
}

export interface Scene {
  /** File name of the capture: lowercase, digits and dashes. */
  id: string;
  title: string;
  steps: SceneStep[];
  /** Captured as an animated image of the whole run, instead of a still of the end. */
  animated?: boolean;
  /** CSS selector of the element the capture is cropped to, with a margin. The whole screen when unset. */
  crop?: string;
}

/** A screen area in CSS pixels. */
export interface Area {
  x: number;
  y: number;
  width: number;
  height: number;
}

const CARD = '[role="listbox"]';

const VEHICLE: TargetOption[] = [
  { label: "Lock vehicle", icon: "lock", enabled: true, hold: 0, submenu: false, cooldown: 0 },
  { label: "Trunk", icon: "box-open", description: "Plate 72UGC014", enabled: true, hold: 0, submenu: false, cooldown: 0 },
  { label: "Doors", icon: "door-open", enabled: true, hold: 0, submenu: true, cooldown: 0 },
  { label: "Hotwire", icon: "fa-solid fa-screwdriver-wrench", badge: "new", enabled: true, hold: 2500, submenu: false, cooldown: 0 },
  { label: "Impound", icon: "siren", enabled: false, reason: Reason.Job, hold: 0, submenu: false, cooldown: 0 },
  { label: "Honk", icon: "info", enabled: false, reason: Reason.Cooldown, hold: 0, submenu: false, cooldown: 4000 },
];

/** Aiming at a car, as Lua sends it. */
function aim(layout: Layout = Layout.Anchored, wait = 800): SceneStep[] {
  return [
    { send: { action: NuiAction.Aim, payload: { active: true, layout } } },
    { send: { action: NuiAction.Options, payload: { options: VEHICLE, selected: 1, depth: 0, kind: Kind.Vehicle } } },
    { send: { action: NuiAction.Anchor, payload: { visible: true, x: 0.42, y: 0.55 } }, wait },
  ];
}

export const SCENES: Scene[] = [
  { id: "target-vehicle", title: "Options on a car", crop: CARD, steps: aim() },
  { id: "target-list", title: "List layout", crop: CARD, steps: aim(Layout.List) },
  {
    id: "target-denied",
    title: "Refused by the server",
    crop: CARD,
    steps: [...aim(Layout.Anchored, 400), { send: { action: NuiAction.Result, payload: { index: 2, ok: false, error: "no_permission" } }, wait: 400 }],
  },
  {
    id: "target-hold",
    title: "Hold to confirm",
    animated: true,
    crop: CARD,
    steps: [
      ...aim(Layout.Anchored, 900),
      { send: { action: NuiAction.Select, payload: { index: 2 } }, wait: 450 },
      { send: { action: NuiAction.Select, payload: { index: 3 } }, wait: 450 },
      { send: { action: NuiAction.Select, payload: { index: 4 } }, wait: 500 },
      { send: { action: NuiAction.Hold, payload: { index: 4, duration: 2500 } }, wait: 2600 },
      { send: { action: NuiAction.Result, payload: { index: 4, ok: true } }, wait: 1500 },
    ],
  },
];


/**
 * Plays a scene through `send`. Resolves after the last step's pause, with the area the crop element covered after
 * any step, or null without a crop or when it never showed.
 */
export async function playScene(scene: Scene, send: (message: NuiMessage) => void): Promise<Area | null> {
  let area: Area | null = null;

  for (const step of scene.steps) {
    if (step.send) {
      send(step.send);
    }

    if (step.click) {
      document.querySelector<HTMLElement>(step.click)?.click();
    }

    await new Promise((resolve) => setTimeout(resolve, step.wait ?? 0));

    const box = scene.crop ? document.querySelector(scene.crop)?.getBoundingClientRect() : undefined;

    if (box && box.width > 0) {
      const left = Math.min(area?.x ?? box.left, box.left);
      const top = Math.min(area?.y ?? box.top, box.top);
      const right = Math.max(area ? area.x + area.width : box.right, box.right);
      const bottom = Math.max(area ? area.y + area.height : box.bottom, box.bottom);

      area = { x: left, y: top, width: right - left, height: bottom - top };
    }
  }

  return area;
}
