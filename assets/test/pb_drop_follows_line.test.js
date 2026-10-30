// SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
//
// SPDX-License-Identifier: Apache-2.0

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import hooks from "../js/index.js";

// WHAT THE LINE SAYS IS WHERE THE DROP LANDS.
//
// A user building a landing page dropped a Section near the bottom of the canvas and watched it
// land inside the section above, somewhere the blue line had never been. Two things let the line
// and the drop disagree:
//
//   * the drop was resolved a SECOND time, against the page as it was by then — and near an edge
//     the page is scrolling under a pointer that is standing still, which sends no `dragover` of
//     its own, so the line was still on the box the pointer had left;
//   * a line drawn before the server's verdict arrived was the optimistic guess, and stayed that
//     guess until the pointer moved.
//
// So the line is drawn again whenever the page moves under the pointer or the verdict lands, and
// the drop takes the spot the line shows.
const TEMPLATE_MIME = "application/x-pb-template";

function transfer(entries = {}) {
  const data = { ...entries };

  return {
    get types() {
      return Object.keys(data);
    },
    effectAllowed: "copy",
    dropEffect: "copy",
    setData: (type, value) => (data[type] = value),
    getData: (type) => data[type] || "",
  };
}

const at = (type, target, dataTransfer, clientY) => ({
  type,
  target,
  dataTransfer,
  clientX: 150,
  clientY,
  preventDefault: () => {},
  stopPropagation: () => {},
  relatedTarget: null,
});

const box = (top, height) => () => ({
  left: 0,
  right: 300,
  top,
  bottom: top + height,
  width: 300,
  height,
});

let mounted = [];
let frames = [];

function mount(el) {
  const handlers = {};
  const pushed = [];
  const ctx = {
    el,
    handlers,
    pushed,
    pushEvent: (name, payload) => pushed.push([name, payload]),
    handleEvent: (name, fn) => (handlers[name] = fn),
  };

  hooks.PbCanvas.mounted.call(ctx);
  mounted.push(ctx);
  return ctx;
}

// Two sections stacked in the canvas root, the frame 300px tall: a pointer at y = 290 is inside the
// bottom edge's scroll band.
function canvas() {
  const el = document.createElement("div");
  el.id = "pb-canvas-root";
  el.getBoundingClientRect = box(0, 600);
  document.body.appendChild(el);

  const node = (id, top, height) => {
    const section = document.createElement("section");
    section.dataset.nodeId = id;
    section.dataset.kind = "tag";
    section.getBoundingClientRect = box(top, height);
    el.appendChild(section);
    return section;
  };

  return { el, first: node("nfirst000", 200, 100), second: node("nsecond00", 300, 150) };
}

const indicator = (ctx) => ctx.indicator.style;

// The outline drawn around a container the drop would go INTO, rather than a line beside a node.
const inside = (ctx) => indicator(ctx).display === "block" && indicator(ctx).borderRadius === "8px";

beforeEach(() => {
  document.body.innerHTML = "";
  window.__pbDropHints = null;
  frames = [];

  vi.stubGlobal("requestAnimationFrame", (fn) => frames.push(fn));
  vi.stubGlobal("cancelAnimationFrame", () => {});

  Object.defineProperty(document.documentElement, "clientHeight", {
    configurable: true,
    get: () => 300,
  });

  Object.defineProperty(document, "scrollingElement", {
    configurable: true,
    value: { scrollTop: 0 },
  });
});

afterEach(() => {
  for (const ctx of mounted) hooks.PbCanvas.destroyed?.call(ctx);
  mounted = [];
  vi.unstubAllGlobals();
  delete document.elementFromPoint;
});

describe("a drop on the canvas", () => {
  it("lands where the line was drawn, not where a second reading of the page puts it", () => {
    const { el, first } = canvas();
    const ctx = mount(el);
    const dt = transfer({ [TEMPLATE_MIME]: "<section></section>" });

    // The lower half of the first section: the line goes under it.
    ctx.onDragOver(at("dragover", first, dt, 290));
    expect(indicator(ctx).transform).toContain(", 300px,");

    // The page moves before the browser fires the drop, with no frame in between to redraw: the
    // same point is now in the section's top half.
    first.getBoundingClientRect = box(270, 100);
    ctx.forgetRects();

    ctx.onDrop(at("drop", first, dt, 290));

    const [name, payload] = ctx.pushed.at(-1);
    expect(name).toBe("drop");
    expect(payload.anchor_id).toBe("nfirst000");
    expect(payload.anchor_before, "the line was under the section").toBe(false);
  });

  it("and a drop with no line before it is still resolved where the browser aimed it", () => {
    const { el, first } = canvas();
    const ctx = mount(el);
    const dt = transfer({ [TEMPLATE_MIME]: "<section></section>" });

    ctx.onDrop(at("drop", first, dt, 210));

    const [, payload] = ctx.pushed.at(-1);
    expect(payload.anchor_id).toBe("nfirst000");
    expect(payload.anchor_before).toBe(true);
  });
});

describe("a pointer resting at the canvas's edge while the page scrolls", () => {
  it("has the line follow whatever slides under it, and the drop follows the line", () => {
    const { el, first, second } = canvas();
    const ctx = mount(el);
    const dt = transfer({ [TEMPLATE_MIME]: "<section></section>" });

    ctx.onDragOver(at("dragover", first, dt, 290));
    expect(indicator(ctx).transform).toContain(", 300px,");
    expect(frames.length, "the edge starts the scroll").toBeGreaterThan(0);

    // One frame of scrolling: the pointer has not moved, and the middle of the second section is
    // under it now. No `dragover` is fired for that.
    first.getBoundingClientRect = box(140, 100);
    second.getBoundingClientRect = box(240, 100);
    document.elementFromPoint = () => second;
    frames.shift()();

    expect(document.scrollingElement.scrollTop).toBeGreaterThan(0);
    expect(inside(ctx), "the line is around the second section now").toBe(true);

    ctx.onDrop(at("drop", second, dt, 290));

    const [, payload] = ctx.pushed.at(-1);
    expect(payload.parent_id).toBe("nsecond00");
  });
});

describe("the server's verdict arriving while the pointer is still", () => {
  it("takes back an 'inside' the guess offered, for a drag begun on the canvas", () => {
    const { el, first } = canvas();
    const ctx = mount(el);
    document.elementFromPoint = () => first;
    ctx.dragging = "nmoving00";
    const dt = transfer({ "application/x-pb-node": "nmoving00" });

    // Dead centre of the first section, before any verdict: the optimistic guess is "inside".
    ctx.onDragOver(at("dragover", first, dt, 250));
    expect(inside(ctx)).toBe(true);

    ctx.handlers["pb:drop-hints"]({ accepts: { nfirst000: false } });

    expect(inside(ctx), "the line moved beside the section without the pointer moving").toBe(false);

    ctx.onDrop(at("drop", first, dt, 250));

    const [, payload] = ctx.pushed.at(-1);
    expect(payload.parent_id).not.toBe("nfirst000");
    expect(payload.anchor_id).toBe("nfirst000");
  });

  it("and for a palette card, whose verdict the chrome hands in", () => {
    const { el, first } = canvas();
    const ctx = mount(el);
    document.elementFromPoint = () => first;
    const dt = transfer({ [TEMPLATE_MIME]: "<footer></footer>" });

    ctx.onDragOver(at("dragover", first, dt, 250));
    expect(inside(ctx)).toBe(true);

    window.__pbDropHints = { nfirst000: false };
    window.dispatchEvent(new Event("pb:hints"));

    expect(inside(ctx)).toBe(false);
  });
});

describe("a drop let go before the server's verdict", () => {
  // The line was the optimistic "inside", and the server may refuse the box. Once the verdict is in
  // the line goes beside a box that refuses, in front of it from its first half, so the drop tells
  // the server which half it was let go over and the fallback lands where that line would have been.
  it("tells the server which half of the box it was let go over", () => {
    const { el, first } = canvas();
    const ctx = mount(el);
    const dt = transfer({ [TEMPLATE_MIME]: "<section></section>" });

    for (const [y, before] of [
      [240, true],
      [260, false],
    ]) {
      ctx.onDragOver(at("dragover", first, dt, y));
      expect(inside(ctx)).toBe(true);

      ctx.onDrop(at("drop", first, dt, y));

      const [, payload] = ctx.pushed.at(-1);
      expect(payload).toMatchObject({ parent_id: "nfirst000", index: 9999 });
      expect(payload.fallback_before, `let go at ${y}`).toBe(before);
    }
  });
});
