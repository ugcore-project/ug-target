/*

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { motion } from "framer-motion";
import { BRAND_TO, PRIMARY, RETICLE } from "@/lib/theme";
import { Reticle as ReticleStyle } from "@/types/protocol";

const CORNERS = [
  { rotate: 0, x: -1, y: -1 },
  { rotate: 90, x: 1, y: -1 },
  { rotate: 180, x: 1, y: 1 },
  { rotate: 270, x: -1, y: 1 },
];

/** The crosshair. Idle it breathes; locked on something with options it snaps brackets around the aim. */
export function Reticle({ locked, style = ReticleStyle.Brackets }: { locked: boolean; style?: ReticleStyle }) {
  if (style === ReticleStyle.None) {
    return null;
  }

  return (
    <div className="pointer-events-none absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2" data-testid="reticle" data-locked={locked} data-style={style}>
      <motion.div
        className="absolute left-1/2 top-1/2 rounded-full"
        style={{ x: "-50%", y: "-50%", backgroundColor: locked ? PRIMARY : RETICLE, opacity: locked ? 1 : 0.9, boxShadow: "0 0 6px rgba(0,0,0,0.6)" }}
        animate={{ width: locked ? 6 : 4, height: locked ? 6 : 4 }}
        transition={{ type: "spring", stiffness: 500, damping: 28 }}
      />
      {style === ReticleStyle.Brackets && (
      <>
      <motion.svg
        className="absolute left-1/2 top-1/2"
        width={44}
        height={44}
        viewBox="0 0 44 44"
        style={{ x: "-50%", y: "-50%" }}
        animate={locked ? { rotate: 0, scale: 1, opacity: 1 } : { rotate: 360, scale: 0.7, opacity: 0.55 }}
        transition={locked ? { type: "spring", stiffness: 380, damping: 26 } : { rotate: { repeat: Infinity, duration: 6, ease: "linear" }, default: { duration: 0.25 } }}
      >
        <defs>
          <linearGradient id="ug-target-reticle" x1="1" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor={PRIMARY} />
            <stop offset="1" stopColor={BRAND_TO} />
          </linearGradient>
        </defs>
        <circle
          cx={22}
          cy={22}
          r={14}
          fill="none"
          stroke={locked ? "url(#ug-target-reticle)" : RETICLE}
          strokeOpacity={locked ? 1 : 0.85}
          strokeWidth={1.5}
          strokeDasharray={locked ? "88 0" : "6 5"}
          style={{ filter: "drop-shadow(0 0 2px rgba(0,0,0,0.7))" }}
        />
      </motion.svg>
      {CORNERS.map((corner) => (
        <motion.svg
          key={corner.rotate}
          className="absolute left-1/2 top-1/2"
          width={10}
          height={10}
          viewBox="0 0 10 10"
          initial={false}
          style={{ rotate: corner.rotate, marginLeft: -5, marginTop: -5 }}
          animate={locked ? { x: corner.x * 24, y: corner.y * 24, opacity: 1 } : { x: corner.x * 34, y: corner.y * 34, opacity: 0 }}
          transition={{ type: "spring", stiffness: 420, damping: 24 }}
        >
          <path d="M1 9 V1 H9" fill="none" stroke={PRIMARY} strokeWidth={2} strokeLinecap="round" />
        </motion.svg>
      ))}
      </>
      )}
    </div>
  );
}
