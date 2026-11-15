/*

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// Page state. Lua owns the target: the page shows what it is told and posts intents in cursor mode only.
// Messages are untrusted shapes until checked here.

import { create } from "zustand";
import { applyTheme, OPTION_COLORS } from "@/lib/theme";
import {
  Layout,
  NuiAction,
  Reason,
  Reticle,
  Side,
  type AnchorPayload,
  type Look,
  type Kind,
  type NuiMessage,
  type PageConfig,
  type ResultPayload,
  type TargetOption,
} from "@/types/protocol";

export const DEFAULT_LOOK: Look = {
  cardWidth: 288,
  cardOpacity: 0.7,
  blur: true,
  side: Side.Auto,
  connector: true,
  pulse: true,
  reticle: Reticle.Brackets,
  hints: true,
  animations: true,
  resultDuration: 1400,
};

const HEX = /^#[0-9a-f]{6}$/i;

export interface HoldState {
  index: number;
  duration: number;
  /** Changes on every start, so the ring restarts. */
  key: number;
}

export interface ResultState extends ResultPayload {
  key: number;
}

export interface TargetState {
  labels: Record<string, string>;
  layout: Layout;
  look: Look;
  optionColors: string[];
  /** The owner lets left click free the cursor. */
  cursorEnabled: boolean;
  numberKeys: boolean;
  open: boolean;
  options: TargetOption[];
  selected: number;
  depth: number;
  kind: Kind | null;
  anchor: AnchorPayload;
  hold: HoldState | null;
  result: ResultState | null;
  cursor: boolean;
  /** Changes when Lua sends a new menu, so rows animate in again. */
  menuKey: number;
  select: (index: number) => void;
}

const REASONS = new Set<string>(Object.values(Reason));
const readReason = (value: unknown): Reason | undefined =>
  typeof value === "string" && REASONS.has(value) ? (value as Reason) : undefined;

const HIDDEN: AnchorPayload = { visible: false, x: 0.5, y: 0.5 };
let counter = 0;

export const useTarget = create<TargetState>((set) => ({
  labels: {},
  layout: Layout.Anchored,
  look: DEFAULT_LOOK,
  optionColors: OPTION_COLORS,
  cursorEnabled: true,
  numberKeys: true,
  open: false,
  options: [],
  selected: 1,
  depth: 0,
  kind: null,
  anchor: HIDDEN,
  hold: null,
  result: null,
  cursor: false,
  menuKey: 0,
  select: (index) => set({ selected: index }),
}));

/** A label in the configured language, or the fallback. */
export function label(labels: Record<string, string>, key: string, fallback: string): string {
  const text = labels[key];

  return typeof text === "string" && text !== "" && text !== `page.${key}` ? text : fallback;
}

const isObject = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null;
const isNumber = (value: unknown): value is number => typeof value === "number" && Number.isFinite(value);
const text = (value: unknown, max: number): string | undefined =>
  typeof value === "string" && value !== "" ? value.slice(0, max) : undefined;

function within(value: unknown, min: number, max: number, fallback: number): number {
  return isNumber(value) ? Math.min(Math.max(value, min), max) : fallback;
}

function oneOf<T extends string>(value: unknown, values: Record<string, T>, fallback: T): T {
  return typeof value === "string" && (Object.values(values) as string[]).includes(value) ? (value as T) : fallback;
}

/** The owner's look from Lua. Lua checked it; it is checked again, field by field. */
export function readLook(value: unknown): Look {
  if (!isObject(value)) {
    return DEFAULT_LOOK;
  }

  const flag = (key: keyof Look) => (typeof value[key] === "boolean" ? (value[key] as boolean) : (DEFAULT_LOOK[key] as boolean));

  return {
    cardWidth: Math.round(within(value.cardWidth, 200, 480, DEFAULT_LOOK.cardWidth)),
    cardOpacity: within(value.cardOpacity, 0, 1, DEFAULT_LOOK.cardOpacity),
    blur: flag("blur"),
    side: oneOf(value.side, Side, DEFAULT_LOOK.side),
    connector: flag("connector"),
    pulse: flag("pulse"),
    reticle: oneOf(value.reticle, Reticle, DEFAULT_LOOK.reticle),
    hints: flag("hints"),
    animations: flag("animations"),
    resultDuration: Math.round(within(value.resultDuration, 300, 5000, DEFAULT_LOOK.resultDuration)),
  };
}

function readColors(value: unknown): string[] {
  // Lua sends an empty table as an empty object.
  if (isObject(value) && !Array.isArray(value) && Object.keys(value).length === 0) {
    return [];
  }

  return Array.isArray(value) ? value.filter((entry): entry is string => typeof entry === "string" && HEX.test(entry)).slice(0, 16) : OPTION_COLORS;
}

function readOption(value: unknown): TargetOption | null {
  if (!isObject(value) || typeof value.label !== "string") {
    return null;
  }

  const option: TargetOption = {
    label: value.label.slice(0, 64),
    enabled: value.enabled === true,
    hold: isNumber(value.hold) ? Math.max(0, value.hold) : 0,
    submenu: value.submenu === true,
    cooldown: isNumber(value.cooldown) ? Math.max(0, value.cooldown) : 0,
  };
  const icon = text(value.icon, 64);
  const iconColor = text(value.iconColor, 32);
  const description = text(value.description, 128);
  const badge = text(value.badge, 16);
  const reason = readReason(value.reason);

  if (icon) option.icon = icon;
  if (iconColor) option.iconColor = iconColor;
  if (description) option.description = description;
  if (badge) option.badge = badge;
  if (reason) option.reason = reason;

  return option;
}

/** Applies one message from Lua. */
export function handleMessage(message: NuiMessage): void {
  const payload = message.payload;
  const state = useTarget.getState();

  switch (message.action) {
    case NuiAction.Config: {
      if (!isObject(payload)) {
        return;
      }

      const labels: Record<string, string> = {};

      if (isObject(payload.labels)) {
        for (const [key, value] of Object.entries(payload.labels)) {
          if (typeof value === "string") {
            labels[key] = value;
          }
        }
      }

      applyTheme(isObject(payload.theme) ? (payload.theme as unknown as PageConfig["theme"]) : undefined);
      useTarget.setState({
        labels,
        layout: payload.layout === Layout.List ? Layout.List : Layout.Anchored,
        look: readLook(payload.look),
        optionColors: readColors(payload.optionColors),
        cursorEnabled: payload.cursor !== false,
        numberKeys: payload.numberKeys !== false,
      });

      return;
    }
    case NuiAction.Aim: {
      const layout = isObject(payload) && payload.layout === Layout.List ? Layout.List : state.layout;

      useTarget.setState({ open: true, layout, options: [], anchor: HIDDEN, hold: null, result: null, cursor: false, depth: 0 });

      return;
    }
    case NuiAction.Options: {
      // Lua MAY encode an empty list as an empty object.
      const raw = isObject(payload) && Array.isArray(payload.options) ? payload.options
        : isObject(payload) && isObject(payload.options) && Object.keys(payload.options).length === 0 ? [] : null;

      if (!isObject(payload) || !raw) {
        return;
      }

      const options = raw.slice(0, 64).map(readOption).filter((option): option is TargetOption => option !== null);

      useTarget.setState({
        options,
        selected: isNumber(payload.selected) ? payload.selected : 1,
        depth: isNumber(payload.depth) ? payload.depth : 0,
        kind: typeof payload.kind === "string" ? (payload.kind as Kind) : null,
        menuKey: ++counter,
      });

      return;
    }
    case NuiAction.Anchor: {
      if (isObject(payload) && isNumber(payload.x) && isNumber(payload.y)) {
        useTarget.setState({ anchor: { visible: payload.visible === true, x: payload.x, y: payload.y } });
      }

      return;
    }
    case NuiAction.Select: {
      if (isObject(payload) && isNumber(payload.index)) {
        useTarget.setState({ selected: payload.index });
      }

      return;
    }
    case NuiAction.Hold: {
      if (isObject(payload) && isNumber(payload.index) && isNumber(payload.duration)) {
        useTarget.setState({ hold: { index: payload.index, duration: payload.duration, key: ++counter }, selected: payload.index });
      } else {
        useTarget.setState({ hold: null });
      }

      return;
    }
    case NuiAction.Result: {
      if (!isObject(payload) || !isNumber(payload.index)) {
        return;
      }

      const result: ResultState = { index: payload.index, ok: payload.ok === true, key: ++counter };
      const reason = readReason(payload.reason);
      const error = text(payload.error, 32);

      if (reason) result.reason = reason;
      if (error) result.error = error;

      useTarget.setState({ result, hold: null });

      return;
    }
    case NuiAction.Cursor: {
      useTarget.setState({ cursor: isObject(payload) && payload.active === true });

      return;
    }
    case NuiAction.Close: {
      useTarget.setState({ open: false, options: [], hold: null, cursor: false, anchor: HIDDEN });

      return;
    }
  }
}

/** Listens for Lua messages. Returns the cleanup. */
export function installMessages(): () => void {
  const listener = (event: MessageEvent) => {
    if (isObject(event.data) && typeof event.data.action === "string") {
      handleMessage(event.data as unknown as NuiMessage);
    }
  };

  window.addEventListener("message", listener);

  return () => window.removeEventListener("message", listener);
}
