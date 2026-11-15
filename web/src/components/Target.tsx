/*

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { AnimatePresence, motion } from "framer-motion";
import { ChevronLeft, MousePointer2 } from "lucide-react";
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { OptionRow } from "@/components/OptionRow";
import { Reticle } from "@/components/Reticle";
import { cn } from "@/lib/cn";
import { sendBack, sendHover, sendPick, sendRelease } from "@/lib/nui";
import { BRAND_TO, PRIMARY } from "@/lib/theme";
import { label, useTarget } from "@/store/targetStore";
import { Layout, Side } from "@/types/protocol";

const GAP = 44;
const EDGE = 16;

function useViewport() {
  const [size, setSize] = useState({ width: window.innerWidth, height: window.innerHeight });

  useEffect(() => {
    const onResize = () => setSize({ width: window.innerWidth, height: window.innerHeight });

    window.addEventListener("resize", onResize);

    return () => window.removeEventListener("resize", onResize);
  }, []);

  return size;
}

/** Where the card goes: beside the anchor, or beside the crosshair. On the owner's side, or flipped left near the right edge. */
function placeCard(anchored: boolean, x: number, y: number, viewport: { width: number; height: number }, height: number, width: number, side: Side) {
  const px = anchored ? x * viewport.width : viewport.width / 2;
  const py = anchored ? y * viewport.height : viewport.height / 2;
  const flip = side === Side.Left || (side === Side.Auto && px + GAP + width > viewport.width - EDGE);
  const left = flip ? px - GAP - width : px + GAP;
  const top = Math.min(Math.max(py - 28, EDGE), viewport.height - height - EDGE);

  return { px, py, left: Math.max(left, EDGE), top, flip };
}

export function Target() {
  const state = useTarget();
  const viewport = useViewport();
  const cardRef = useRef<HTMLDivElement>(null);
  const [height, setHeight] = useState(120);
  const { open, options, layout, anchor, labels, cursor, depth, result, look } = state;
  const visible = open && options.length > 0;
  const anchored = layout === Layout.Anchored && anchor.visible;
  const place = placeCard(anchored, anchor.x, anchor.y, viewport, height, look.cardWidth, look.side);

  useLayoutEffect(() => {
    if (cardRef.current) {
      setHeight(cardRef.current.offsetHeight);
    }
  }, [options.length, depth, visible]);

  useEffect(() => {
    if (!result) {
      return;
    }

    const timer = setTimeout(() => {
      if (useTarget.getState().result?.key === result.key) {
        useTarget.setState({ result: null });
      }
    }, look.resultDuration);

    return () => clearTimeout(timer);
  }, [result, look.resultDuration]);

  useEffect(() => {
    if (!cursor) {
      return;
    }

    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape" || event.key === "Backspace") {
        event.preventDefault();
        void sendBack();
      }
    };
    const onContext = (event: MouseEvent) => {
      event.preventDefault();
      void sendBack();
    };

    window.addEventListener("keydown", onKey);
    window.addEventListener("contextmenu", onContext);

    return () => {
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("contextmenu", onContext);
    };
  }, [cursor]);

  if (!open) {
    return null;
  }

  const hover = (index: number) => {
    if (useTarget.getState().selected !== index) {
      state.select(index);
      void sendHover(index);
    }
  };

  // The line starts at the anchor and ends at the card's near edge.
  const lineEnd = place.flip ? place.left + look.cardWidth : place.left;

  return (
    <div className={cn("fixed inset-0 select-none", !cursor && "pointer-events-none")} data-testid="target">
      <Reticle locked={visible} style={look.reticle} />

      <AnimatePresence>
        {visible && anchored && (look.connector || look.pulse) && (
          <motion.svg
            key="connector"
            data-testid="connector"
            className="pointer-events-none absolute inset-0 h-full w-full"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
          >
            <defs>
              <linearGradient id="ug-target-connector" gradientUnits="userSpaceOnUse" x1={place.px} y1={place.py} x2={lineEnd} y2={place.top + 26}>
                <stop offset="0" stopColor={PRIMARY} />
                <stop offset="1" stopColor={BRAND_TO} />
              </linearGradient>
            </defs>
            {look.connector && (
            <motion.line
              x1={place.px}
              y1={place.py}
              animate={{ x2: lineEnd, y2: place.top + 26 }}
              initial={false}
              stroke="url(#ug-target-connector)"
              strokeOpacity={0.8}
              strokeWidth={1.5}
              strokeDasharray="3 4"
            />
            )}
            <circle cx={place.px} cy={place.py} r={4} fill={PRIMARY} />
            {look.pulse && (
            <motion.circle
              cx={place.px}
              cy={place.py}
              fill="none"
              stroke={PRIMARY}
              strokeWidth={1.5}
              initial={{ r: 4, opacity: 0.8 }}
              animate={{ r: 14, opacity: 0 }}
              transition={{ repeat: Infinity, duration: 1.4, ease: "easeOut" }}
            />
            )}
          </motion.svg>
        )}
      </AnimatePresence>

      <AnimatePresence>
        {visible && (
          <motion.div
            key="card"
            ref={cardRef}
            role="listbox"
            aria-label="Target options"
            className={cn("absolute overflow-hidden rounded-2xl border border-white/10 p-1.5 pt-2 text-foreground shadow-ug-lg", look.blur && "backdrop-blur-md")}
            style={{ width: look.cardWidth, backgroundColor: `hsl(var(--ug-background) / ${look.cardOpacity})` }}
            initial={{ opacity: 0, scale: 0.92, left: place.left, top: place.top }}
            animate={{ opacity: 1, scale: 1, left: place.left, top: place.top }}
            exit={{ opacity: 0, scale: 0.92, transition: { duration: 0.12 } }}
            transition={{ type: "spring", stiffness: 520, damping: 38, mass: 0.6 }}
          >
            <div className="absolute inset-x-0 top-0 h-0.5 bg-gradient-to-r from-primary to-brand-to" />
            {depth > 0 && (
              <button
                type="button"
                className={cn("mb-1 flex items-center gap-1 rounded-md px-2 py-1 text-xs text-muted-foreground", cursor ? "hover:text-foreground" : "pointer-events-none")}
                onClick={() => void sendBack()}
              >
                <ChevronLeft className="h-3.5 w-3.5" />
                {label(labels, "back", "Back")}
              </button>
            )}

            <motion.ul key={state.menuKey} initial="hidden" animate="shown" transition={{ staggerChildren: 0.035 }} className="flex flex-col gap-0.5">
              {options.map((option, offset) => (
                <OptionRow
                  key={`${state.menuKey}-${offset}`}
                  option={option}
                  index={offset + 1}
                  selected={state.selected === offset + 1}
                  labels={labels}
                  hold={state.hold}
                  result={result}
                  colors={state.optionColors}
                  numbers={state.numberKeys}
                  cursor={cursor}
                  onHover={hover}
                  onPick={(index) => void sendPick(index)}
                  onRelease={() => void sendRelease()}
                />
              ))}
            </motion.ul>

            {look.hints && (cursor || state.cursorEnabled) && (
            <div data-testid="hints" className="mt-1 flex items-center justify-end gap-1.5 border-t border-white/10 px-2 pt-1.5 text-[10px] text-muted-foreground">
              {cursor ? (
                <span className="flex items-center gap-1" data-testid="cursor-hint">
                  <MousePointer2 className="h-3 w-3 text-primary" />
                  {label(labels, "back", "Back")}: Esc
                </span>
              ) : (
                <span>{label(labels, "cursor", "Click for cursor")}</span>
              )}
            </div>
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
