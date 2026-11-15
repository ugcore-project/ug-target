/*

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { MotionConfig } from "framer-motion";
import { lazy, Suspense, useEffect } from "react";
import { Target } from "@/components/Target";
import { isEnvBrowser, sendReady } from "@/lib/nui";
import { installMessages, useTarget } from "@/store/targetStore";

// Dev only: removed from production builds.
// Dev and showcase builds only: removed from production builds.
const Preview = import.meta.env.DEV || import.meta.env.MODE === "showcase" ? lazy(() => import("@/dev/Preview")) : null;

export default function App() {
  const animations = useTarget((state) => state.look.animations);

  useEffect(() => {
    const uninstall = installMessages();

    void sendReady();

    return uninstall;
  }, []);

  return (
    <MotionConfig reducedMotion={animations ? "user" : "always"}>
      <Target />
      {Preview && isEnvBrowser() && (
        <Suspense fallback={null}>
          <Preview />
        </Suspense>
      )}
    </MotionConfig>
  );
}
