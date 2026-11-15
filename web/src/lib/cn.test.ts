/*

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { describe, expect, it } from "vitest";
import { cn } from "@/lib/cn";

describe("cn", () => {
  it("joins static classes", () => {
    expect(cn("a", "b")).toBe("a b");
  });

  it("drops falsy values", () => {
    const hidden = false;

    expect(cn("a", hidden && "b", undefined, null, "c")).toBe("a c");
  });

  it("lets a later conflicting Tailwind class win", () => {
    expect(cn("bg-red-500", "bg-blue-500")).toBe("bg-blue-500");
  });
});
