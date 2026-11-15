/*

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// Messages between client/nui.lua and the page. Values MUST match shared/enums.lua: tests/nui.lua compares them.

export const NuiAction = {
  Config: "config",
  Aim: "aim",
  Options: "options",
  Anchor: "anchor",
  Select: "select",
  Hold: "hold",
  Result: "result",
  Cursor: "cursor",
  Close: "close",
} as const;
export type NuiAction = (typeof NuiAction)[keyof typeof NuiAction];

export const NuiCallback = {
  Ready: "ready",
  Hover: "hover",
  Pick: "pick",
  Release: "release",
  Back: "back",
} as const;
export type NuiCallback = (typeof NuiCallback)[keyof typeof NuiCallback];

export const Layout = {
  Anchored: "anchored",
  List: "list",
} as const;
export type Layout = (typeof Layout)[keyof typeof Layout];

export const Reticle = {
  Brackets: "brackets",
  Dot: "dot",
  None: "none",
} as const;
export type Reticle = (typeof Reticle)[keyof typeof Reticle];

export const Side = {
  Auto: "auto",
  Left: "left",
  Right: "right",
} as const;
export type Side = (typeof Side)[keyof typeof Side];

export const Reason = {
  Job: "job",
  Gang: "gang",
  Duty: "duty",
  Items: "items",
  Vehicle: "vehicle",
  Cooldown: "cooldown",
  Busy: "busy",
} as const;
export type Reason = (typeof Reason)[keyof typeof Reason];

export const Kind = {
  Ped: "ped",
  Vehicle: "vehicle",
  Object: "object",
  Player: "player",
  Zone: "zone",
} as const;
export type Kind = (typeof Kind)[keyof typeof Kind];

export interface ThemeConfig {
  mode: string;
  colors: Record<string, string>;
  radius: string;
  font: string;
  scale: number;
}

/** How the options look: config.lua's `look`. */
export interface Look {
  cardWidth: number;
  cardOpacity: number;
  blur: boolean;
  side: Side;
  connector: boolean;
  pulse: boolean;
  reticle: Reticle;
  hints: boolean;
  animations: boolean;
  resultDuration: number;
}

export interface PageConfig {
  theme?: ThemeConfig;
  labels: Record<string, string>;
  locale: string;
  layout: Layout;
  look?: Partial<Look>;
  /** Hex row colors. Empty: every row takes the theme's primary. */
  optionColors?: string[];
  /** Left click frees the cursor. */
  cursor?: boolean;
  /** Number keys pick rows, and rows show their number. */
  numberKeys?: boolean;
}

export interface TargetOption {
  label: string;
  icon?: string;
  iconColor?: string;
  description?: string;
  badge?: string;
  enabled: boolean;
  reason?: Reason;
  /** Milliseconds to hold, 0 for none. */
  hold: number;
  /** Opens a submenu. */
  submenu: boolean;
  /** Milliseconds left on the cooldown, 0 for none. */
  cooldown: number;
}

export interface OptionsPayload {
  options: TargetOption[];
  /** 1-based, like the number keys. */
  selected: number;
  depth: number;
  kind: Kind;
}

export interface AnchorPayload {
  visible: boolean;
  /** Screen fractions, 0 to 1. */
  x: number;
  y: number;
}

export interface HoldPayload {
  index?: number;
  duration?: number;
}

export interface ResultPayload {
  index: number;
  ok: boolean;
  reason?: Reason;
  error?: string;
}

export interface NuiMessage {
  action: NuiAction;
  payload?: unknown;
}
