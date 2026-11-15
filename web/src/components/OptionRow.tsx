/*

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { motion } from "framer-motion";
import { Check, ChevronRight, Lock, TimerReset } from "lucide-react";
import { cn } from "@/lib/cn";
import { iconFor, safeColor } from "@/lib/icons";
import { PRIMARY } from "@/lib/theme";
import { label, type HoldState, type ResultState } from "@/store/targetStore";
import type { TargetOption } from "@/types/protocol";

const RING = 2 * Math.PI * 15;

interface Props {
  option: TargetOption;
  index: number;
  selected: boolean;
  labels: Record<string, string>;
  hold: HoldState | null;
  result: ResultState | null;
  cursor: boolean;
  /** The owner's row colors. Empty: the theme's primary. */
  colors: string[];
  /** Show the number key. */
  numbers: boolean;
  onHover: (index: number) => void;
  onPick: (index: number) => void;
  onRelease: () => void;
}

/** One option: number key, icon, label, and its state (hold ring, cooldown, reason, result). */
export function OptionRow({ option, index, selected, labels, hold, result, cursor, colors, numbers, onHover, onPick, onRelease }: Props) {
  const Icon = iconFor(option.icon);
  // Each row has its own color: the option's icon color, or one from the palette by position, or the primary.
  const own = safeColor(option.iconColor);
  const palette = own ? undefined : colors[(index - 1) % Math.max(colors.length, 1)];
  const color = own ?? palette ?? PRIMARY;
  // Palette colors are #rrggbb, so a tint can append an alpha. An option's own color MAY be a name.
  const tint = (alpha: string) => (palette ? `${palette}${alpha}` : undefined);
  const holding = hold?.index === index ? hold : null;
  const flash = result?.index === index ? result : null;
  const failed = flash !== null && !flash.ok;
  const reasonText = option.reason ? label(labels, `reason.${option.reason}`, option.reason) : undefined;
  const failText = flash && !flash.ok
    ? flash.reason
      ? label(labels, `reason.${flash.reason}`, flash.reason)
      : label(labels, `error.${flash.error ?? ""}`, label(labels, "failed", "Failed"))
    : undefined;

  return (
    <motion.li
      role="option"
      aria-selected={selected}
      aria-disabled={!option.enabled}
      data-testid={`option-${index}`}
      className={cn("relative flex items-center gap-3 rounded-lg px-2.5 py-2", cursor && "cursor-pointer")}
      variants={{ hidden: { opacity: 0, x: -10 }, shown: { opacity: 1, x: 0 } }}
      transition={{ type: "spring", stiffness: 500, damping: 34 }}
      onPointerEnter={cursor ? () => onHover(index) : undefined}
      onPointerDown={cursor ? () => onPick(index) : undefined}
      onPointerUp={cursor && option.hold > 0 ? onRelease : undefined}
      onPointerLeave={cursor && holding ? onRelease : undefined}
    >
      {selected && (
        <motion.div
          layoutId="ug-target-selection"
          className="absolute inset-0 rounded-lg"
          style={{ backgroundColor: tint("22") ?? "rgb(255 255 255 / 0.08)", boxShadow: `inset 3px 0 0 ${color}` }}
          transition={{ type: "spring", stiffness: 600, damping: 40 }}
        />
      )}

      {numbers && (
      <kbd
        className={cn(
          "relative z-10 flex h-5 w-5 shrink-0 items-center justify-center rounded-md border text-[10px] font-semibold tabular-nums",
          selected ? "border-transparent text-black" : "border-white/15 text-muted-foreground",
        )}
        style={selected ? { backgroundColor: color } : undefined}
      >
        {index <= 9 ? index : "·"}
      </kbd>
      )}

      <div
        className={cn("relative z-10 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg", !option.enabled && "opacity-50")}
        style={{ backgroundColor: tint(selected ? "40" : "26") ?? "rgb(255 255 255 / 0.05)" }}
      >
        {holding && (
          <svg className="absolute -inset-1 h-10 w-10 -rotate-90" viewBox="0 0 34 34" data-testid="hold-ring">
            <motion.circle
              key={holding.key}
              cx={17}
              cy={17}
              r={15}
              fill="none"
              stroke={color}
              strokeWidth={2.5}
              strokeLinecap="round"
              strokeDasharray={RING}
              initial={{ strokeDashoffset: RING }}
              animate={{ strokeDashoffset: 0 }}
              transition={{ duration: holding.duration / 1000, ease: "linear" }}
            />
          </svg>
        )}
        {flash?.ok ? (
          <motion.span initial={{ scale: 0.4 }} animate={{ scale: 1 }} className="text-success">
            <Check className="h-4 w-4" />
          </motion.span>
        ) : (
          <Icon className="h-4 w-4" style={{ color }} />
        )}
      </div>

      <motion.div
        className={cn("relative z-10 min-w-0 flex-1", !option.enabled && "opacity-60")}
        animate={failed ? { x: [0, -6, 6, -4, 4, 0] } : { x: 0 }}
        transition={{ duration: 0.35 }}
      >
        <div className="truncate text-sm font-medium text-foreground">{option.label}</div>
        {failText ? (
          <div className="truncate text-xs text-destructive" data-testid="fail">
            {failText}
          </div>
        ) : !option.enabled && reasonText ? (
          <div className="flex items-center gap-1 truncate text-xs text-warning">
            {option.cooldown > 0 ? <TimerReset className="h-3 w-3" /> : <Lock className="h-3 w-3" />}
            {reasonText}
          </div>
        ) : option.description ? (
          <div className="truncate text-xs text-muted-foreground">{option.description}</div>
        ) : null}
      </motion.div>

      <div className="relative z-10 flex shrink-0 items-center gap-1.5">
        {option.badge && (
          <span className="rounded-full bg-gradient-to-r from-primary to-brand-to px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-primary-foreground">
            {option.badge}
          </span>
        )}
        {option.hold > 0 && option.enabled && !holding && (
          <span className="rounded-md border border-white/15 px-1.5 py-0.5 text-[10px] text-muted-foreground">{label(labels, "hold", "Hold")}</span>
        )}
        {option.submenu && <ChevronRight className="h-4 w-4 text-muted-foreground" />}
      </div>

      {option.cooldown > 0 && (
        <motion.div
          className="absolute bottom-0.5 left-3 right-3 h-0.5 origin-left rounded-full bg-warning/70"
          initial={{ scaleX: 1 }}
          animate={{ scaleX: 0 }}
          transition={{ duration: option.cooldown / 1000, ease: "linear" }}
        />
      )}
    </motion.li>
  );
}
