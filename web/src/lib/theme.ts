/*

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// The owner's ug-lib theme, applied to this page too, so every UgCore screen looks the same. Same rules as ug-lib.

import type { ThemeConfig } from "@/types/protocol";

/** Theme tokens owners MAY override, mapped to their CSS variable. */
const THEME_TOKENS: Record<string, string> = {
  background: "--ug-background",
  foreground: "--ug-foreground",
  card: "--ug-card",
  cardForeground: "--ug-card-foreground",
  popover: "--ug-popover",
  popoverForeground: "--ug-popover-foreground",
  primary: "--ug-primary",
  primaryForeground: "--ug-primary-foreground",
  secondary: "--ug-secondary",
  secondaryForeground: "--ug-secondary-foreground",
  muted: "--ug-muted",
  mutedForeground: "--ug-muted-foreground",
  accent: "--ug-accent",
  accentForeground: "--ug-accent-foreground",
  destructive: "--ug-destructive",
  destructiveForeground: "--ug-destructive-foreground",
  success: "--ug-success",
  successForeground: "--ug-success-foreground",
  warning: "--ug-warning",
  warningForeground: "--ug-warning-foreground",
  border: "--ug-border",
  input: "--ug-input",
  ring: "--ug-ring",
  brandTo: "--ug-brand-to",
  reticle: "--ug-reticle",
};

/** The theme's primary color, for SVG strokes and inline styles. Same accent as every UgCore screen. */
export const PRIMARY = "hsl(var(--ug-primary))";

/** Where brand gradients end. */
export const BRAND_TO = "hsl(var(--ug-brand-to))";

/** The idle crosshair. */
export const RETICLE = "hsl(var(--ug-reticle))";

/** Option colors, one per row, unless the option sets its own icon color. The owner MAY replace them. */
export const OPTION_COLORS = ["#a78bfa", "#38bdf8", "#34d399", "#fbbf24", "#fb7185", "#e879f9", "#2dd4bf", "#818cf8"];

/** The primary color at an opacity from 0 to 1. */
export const primaryAlpha = (alpha: number): string => `hsl(var(--ug-primary) / ${alpha})`;

const HSL_TRIPLET = /^\d+(\.\d+)? \d+(\.\d+)?% \d+(\.\d+)?%$/;
const SIZE = /^\d*\.?\d+(rem|px)$/;
const FONTS: Record<string, string> = {
  Inter: '"Inter Variable", ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
};

/** Applies theme values to `<html>`. Lua checked them; they are checked again before reaching CSS. */
export function applyTheme(theme: ThemeConfig | undefined): void {
  const root = document.documentElement;

  root.classList.toggle("dark", theme?.mode !== "light");

  for (const [token, cssVar] of Object.entries(THEME_TOKENS)) {
    const value = theme?.colors?.[token];

    if (typeof value === "string" && HSL_TRIPLET.test(value)) {
      root.style.setProperty(cssVar, value);
    } else {
      root.style.removeProperty(cssVar);
    }
  }

  // An owner primary color replaces the whole brand gradient, so it never ends in the default blue, unless the owner
  // set brandTo too.
  const primary = theme?.colors?.primary;
  const brandTo = theme?.colors?.brandTo;

  if (typeof brandTo === "string" && HSL_TRIPLET.test(brandTo)) {
    root.style.setProperty("--ug-brand-to", brandTo);
  } else if (typeof primary === "string" && HSL_TRIPLET.test(primary)) {
    root.style.setProperty("--ug-brand-to", primary);
  } else {
    root.style.removeProperty("--ug-brand-to");
  }

  if (theme && SIZE.test(theme.radius)) {
    root.style.setProperty("--ug-radius", theme.radius);
  }

  const font = theme ? FONTS[theme.font] : undefined;

  if (font) {
    root.style.setProperty("--ug-font-sans", font);
  }

  const scale = theme && Number.isFinite(theme.scale) ? Math.min(Math.max(theme.scale, 0.75), 1.5) : 1;

  root.style.setProperty("--ug-scale", String(scale));
}
