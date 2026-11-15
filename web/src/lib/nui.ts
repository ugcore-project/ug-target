/*

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// The only file that calls `fetch`. NUI callbacks are POSTs to `https://<resource>/<callback>`.
// The page only posts in cursor mode, on pointer moves over a new row and on clicks: far under Lua's budget.

import { NuiCallback } from "@/types/protocol";

declare global {
  interface Window {
    GetParentResourceName?: () => string;
  }
}

/** True in a normal browser (`npm run dev`), where no NUI callback endpoint exists. */
export function isEnvBrowser(): boolean {
  return typeof window.GetParentResourceName !== "function";
}

function resourceName(): string {
  return window.GetParentResourceName?.() ?? "ug-target";
}

/** Sent requests in a browser, for the dev preview and tests. */
export const browserLog: { callback: string; data: unknown }[] = [];

export async function postNui(callback: NuiCallback, data: unknown): Promise<boolean> {
  if (isEnvBrowser()) {
    browserLog.push({ callback, data });

    return true;
  }

  try {
    const response = await fetch(`https://${resourceName()}/${callback}`, {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=UTF-8" },
      body: JSON.stringify(data),
    });
    const reply = (await response.json()) as { ok?: unknown };

    return reply.ok === true;
  } catch {
    return false;
  }
}

export const sendReady = () => postNui(NuiCallback.Ready, {});
export const sendHover = (index: number) => postNui(NuiCallback.Hover, { index });
export const sendPick = (index: number) => postNui(NuiCallback.Pick, { index });
export const sendRelease = () => postNui(NuiCallback.Release, {});
export const sendBack = () => postNui(NuiCallback.Back, {});
