/*

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { readFileSync } from "node:fs";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MotionGlobalConfig } from "framer-motion";
import { beforeEach, describe, expect, it, vi } from "vitest";
import App from "@/App";
import { iconFor, safeColor } from "@/lib/icons";
import { flattenLabels } from "@/lib/labels";
import { DEFAULT_LOOK, handleMessage, readLook, useTarget } from "@/store/targetStore";
import { Kind, Layout, NuiAction, Reason, type TargetOption } from "@/types/protocol";

MotionGlobalConfig.skipAnimations = true;

const nui = vi.hoisted(() => ({
  isEnvBrowser: () => false,
  sendReady: vi.fn(),
  sendHover: vi.fn(),
  sendPick: vi.fn(),
  sendRelease: vi.fn(),
  sendBack: vi.fn(),
}));

vi.mock("@/lib/nui", () => nui);

/** The labels Lua sends: the `page` group of locales/en.json. */
const LABELS = flattenLabels((JSON.parse(readFileSync("../locales/en.json", "utf8")) as { page: Record<string, unknown> }).page);

const option = (change: Partial<TargetOption> = {}): TargetOption => ({
  label: "Trunk",
  enabled: true,
  hold: 0,
  submenu: false,
  cooldown: 0,
  ...change,
});

function open(options: TargetOption[], extra: { depth?: number; selected?: number } = {}) {
  act(() => {
    handleMessage({ action: NuiAction.Aim, payload: { active: true, layout: Layout.Anchored } });
    handleMessage({ action: NuiAction.Options, payload: { options, selected: extra.selected ?? 1, depth: extra.depth ?? 0, kind: Kind.Vehicle } });
    handleMessage({ action: NuiAction.Anchor, payload: { visible: true, x: 0.4, y: 0.5 } });
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  act(() => {
    handleMessage({ action: NuiAction.Close });
    handleMessage({ action: NuiAction.Config, payload: { labels: LABELS, locale: "en", layout: Layout.Anchored } });
  });
});

describe("target", () => {
  it("says it is ready and shows nothing until aiming", () => {
    render(<App />);

    expect(nui.sendReady).toHaveBeenCalledOnce();
    expect(screen.queryByTestId("target")).toBeNull();
  });

  it("shows the reticle idle, then locked with the options", () => {
    render(<App />);
    act(() => handleMessage({ action: NuiAction.Aim, payload: { active: true } }));

    expect(screen.getByTestId("reticle").dataset.locked).toBe("false");

    open([option(), option({ label: "Lock", description: "Your car" })]);

    expect(screen.getByTestId("reticle").dataset.locked).toBe("true");
    expect(screen.getAllByRole("option")).toHaveLength(2);
    expect(screen.getByText("Your car")).toBeTruthy();
    expect(screen.getByTestId("option-1").getAttribute("aria-selected")).toBe("true");
  });

  it("numbers the first nine options", () => {
    render(<App />);
    open(Array.from({ length: 10 }, (_, index) => option({ label: `Option ${index + 1}` })));

    expect(screen.getByTestId("option-9").textContent).toContain("9");
    expect(screen.getByTestId("option-10").textContent).toContain("·");
  });

  it("gives each option its own color, and keeps an option's own icon color", () => {
    render(<App />);
    open([option({ label: "One" }), option({ label: "Two" }), option({ label: "Three", iconColor: "#ff0000" })]);

    const iconColor = (index: number) => screen.getByTestId(`option-${index}`).querySelector("svg")?.getAttribute("style");

    expect(iconColor(1)).toContain("rgb(167, 139, 250)");
    expect(iconColor(2)).toContain("rgb(56, 189, 248)");
    expect(iconColor(3)).toContain("rgb(255, 0, 0)");
  });

  it("follows the selection Lua sends", () => {
    render(<App />);
    open([option(), option({ label: "Lock" })]);
    act(() => handleMessage({ action: NuiAction.Select, payload: { index: 2 } }));

    expect(screen.getByTestId("option-2").getAttribute("aria-selected")).toBe("true");
  });

  it("explains disabled options with the localized reason", () => {
    render(<App />);
    open([option({ enabled: false, reason: Reason.Job }), option({ label: "Honk", enabled: false, reason: Reason.Cooldown, cooldown: 3000 })]);

    expect(screen.getByText("Wrong job")).toBeTruthy();
    expect(screen.getByText("Cooling down")).toBeTruthy();
    expect(screen.getByTestId("option-1").getAttribute("aria-disabled")).toBe("true");
  });

  it("shows a hold ring and the server's refusal", async () => {
    render(<App />);
    open([option({ hold: 2000 })]);

    expect(screen.getByText("Hold")).toBeTruthy();

    act(() => handleMessage({ action: NuiAction.Hold, payload: { index: 1, duration: 2000 } }));

    expect(screen.getByTestId("hold-ring")).toBeTruthy();

    act(() => handleMessage({ action: NuiAction.Result, payload: { index: 1, ok: false, error: "no_permission" } }));

    expect(screen.queryByTestId("hold-ring")).toBeNull();
    expect(screen.getByTestId("fail").textContent).toBe("Not allowed");
    await waitFor(() => expect(screen.queryByTestId("fail")).toBeNull(), { timeout: 2500 });
  });

  it("shows a back row in submenus", () => {
    render(<App />);
    open([option({ label: "Front left" })], { depth: 1 });

    expect(screen.getByText("Back")).toBeTruthy();
  });

  it("ignores the pointer until the cursor is free", () => {
    render(<App />);
    open([option(), option({ label: "Lock" })]);
    fireEvent.pointerDown(screen.getByTestId("option-2"));

    expect(nui.sendPick).not.toHaveBeenCalled();

    act(() => handleMessage({ action: NuiAction.Cursor, payload: { active: true } }));
    fireEvent.pointerEnter(screen.getByTestId("option-2"));
    fireEvent.pointerDown(screen.getByTestId("option-2"));

    expect(nui.sendHover).toHaveBeenCalledWith(2);
    expect(nui.sendPick).toHaveBeenCalledWith(2);
    expect(screen.getByTestId("cursor-hint")).toBeTruthy();

    fireEvent.keyDown(window, { key: "Escape" });
    fireEvent.contextMenu(window);

    expect(nui.sendBack).toHaveBeenCalledTimes(2);
  });

  it("releases a cursor hold when the pointer lets go", () => {
    render(<App />);
    open([option({ hold: 1000 })]);
    act(() => handleMessage({ action: NuiAction.Cursor, payload: { active: true } }));
    fireEvent.pointerUp(screen.getByTestId("option-1"));

    expect(nui.sendRelease).toHaveBeenCalledOnce();
  });

  it("closes", async () => {
    render(<App />);
    open([option()]);
    act(() => handleMessage({ action: NuiAction.Close }));

    await waitFor(() => expect(screen.queryByTestId("target")).toBeNull());
  });

  it("hides the card when Lua sends an empty menu as an object", () => {
    render(<App />);
    act(() => {
      handleMessage({ action: NuiAction.Aim, payload: { active: true, layout: Layout.Anchored } });
      handleMessage({ action: NuiAction.Options, payload: { options: [option()], selected: 1 } });
    });
    expect(screen.getAllByRole("option")).toHaveLength(1);
    act(() => handleMessage({ action: NuiAction.Options, payload: { options: {}, selected: 1 } }));
    expect(useTarget.getState().options).toHaveLength(0);
  });

  it("drops malformed messages", () => {
    render(<App />);
    act(() => {
      handleMessage({ action: NuiAction.Aim, payload: {} });
      handleMessage({ action: NuiAction.Options, payload: { options: [{ label: 5 }, null, option({ reason: "hacked" as Reason })], selected: "x" } });
    });

    expect(screen.getAllByRole("option")).toHaveLength(1);
    expect(useTarget.getState().options[0]?.reason).toBeUndefined();
    expect(useTarget.getState().selected).toBe(1);
  });
});

describe("owner config", () => {
  const configure = (extra: Record<string, unknown>) =>
    act(() => handleMessage({ action: NuiAction.Config, payload: { labels: LABELS, locale: "en", layout: Layout.Anchored, ...extra } }));

  it("sizes, places and dresses the card as the owner set", () => {
    render(<App />);
    configure({ look: { cardWidth: 360, cardOpacity: 0.3, blur: false, side: "left", connector: false, pulse: false, hints: false } });
    open([option()]);

    const card = screen.getByRole("listbox");

    expect(card.style.width).toBe("360px");
    expect(card.style.backgroundColor).toContain("0.3");
    expect(card.className).not.toContain("backdrop-blur");
    // Left of the anchor at 40% of the width.
    expect(Number.parseFloat(card.style.left)).toBeLessThan(window.innerWidth * 0.4);
    expect(screen.queryByTestId("connector")).toBeNull();
    expect(screen.queryByTestId("hints")).toBeNull();
  });

  it("picks the reticle, or none", () => {
    render(<App />);
    configure({ look: { reticle: "dot" } });
    act(() => handleMessage({ action: NuiAction.Aim, payload: { active: true } }));

    expect(screen.getByTestId("reticle").dataset.style).toBe("dot");
    expect(screen.getByTestId("reticle").querySelectorAll("svg")).toHaveLength(0);

    configure({ look: { reticle: "none" } });

    expect(screen.queryByTestId("reticle")).toBeNull();
  });

  it("uses the owner's row colors, the primary when there are none, and hides numbers without number keys", () => {
    render(<App />);
    configure({ optionColors: ["#010203"], numberKeys: false });
    open([option({ label: "One" }), option({ label: "Two" })]);

    const iconColor = (index: number) => screen.getByTestId(`option-${index}`).querySelector("svg")?.getAttribute("style");

    expect(iconColor(2)).toContain("rgb(1, 2, 3)");
    expect(screen.getByTestId("option-1").querySelector("kbd")).toBeNull();

    configure({ optionColors: {} });

    expect(iconColor(1)).toContain("--ug-primary");
  });

  it("drops the cursor hint when the owner turned the cursor off", () => {
    render(<App />);
    configure({ cursor: false });
    open([option()]);

    expect(screen.queryByTestId("hints")).toBeNull();
  });

  it("reads the look field by field, clamped", () => {
    expect(readLook(null)).toEqual(DEFAULT_LOOK);
    expect(readLook({ cardWidth: 9000, side: "up", reticle: "dot", resultDuration: 10, blur: "yes" })).toEqual({
      ...DEFAULT_LOOK,
      cardWidth: 480,
      reticle: "dot",
      resultDuration: 300,
    });
  });
});

describe("icons", () => {
  it("maps lucide and Font Awesome names, with a fallback", () => {
    expect(iconFor("car")).toBe(iconFor("fa-solid fa-car"));
    expect(iconFor("fas fa-lock")).toBe(iconFor("lock"));
    expect(iconFor("nonsense")).toBe(iconFor(undefined));
  });

  it("only accepts plain colors", () => {
    expect(safeColor("#ff0000")).toBe("#ff0000");
    expect(safeColor("red")).toBe("red");
    expect(safeColor("url(javascript:x)")).toBeUndefined();
  });
});
