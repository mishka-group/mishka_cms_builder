// SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
//
// SPDX-License-Identifier: Apache-2.0

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import hooks from "../js/index.js";
import { resolveDrop } from "../js/pb_drop.js";

// A BOX THAT WILL NOT TAKE WHAT IS DRAGGED SAYS SO.
//
// A form dragged over a paragraph used to get a line after the paragraph and nothing else, so it read
// as if the paragraph were an ordinary place to drop into and the editor had moved the drop for no
// reason. The server's verdict (`pb:drop-hints`) now carries WHY each box that could hold children
// and will not refuses (`refusals`, by node id), and the canvas outlines that box, names the rule in
// a chip, and keeps the line where the drop actually goes: right after it.
//
// Legality stays the server's. Nothing here decides what a paragraph may hold; the canvas shows a
// reason only for a box the verdict marked `false` AND gave a reason for.
const TEMPLATE_MIME = "application/x-pb-template";

const REASON = "A <p> can only hold text and inline elements.";

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

// A page of a div holding a paragraph (200..300) with a run of words in it and a section under it
// (300..450). The paragraph is the box a form will not enter.
function page(paragraphTop = 200) {
  const root = document.createElement("div");
  root.id = "pb-canvas-root";
  root.getBoundingClientRect = box(0, 600);
  document.body.appendChild(root);

  const node = (parent, tag, id, kind, top, height) => {
    const el = document.createElement(tag);
    el.dataset.nodeId = id;
    el.dataset.kind = kind;
    el.getBoundingClientRect = box(top, height);
    parent.appendChild(el);
    return el;
  };

  const wrapper = node(root, "div", "nwrapper0", "tag", paragraphTop - 100, 400);
  const paragraph = node(wrapper, "p", "nparagrph", "tag", paragraphTop, 100);
  const words = node(paragraph, "span", "nwords000", "text", paragraphTop, 100);
  const section = node(wrapper, "section", "nsection0", "tag", paragraphTop + 100, 150);

  return { root, wrapper, paragraph, words, section };
}

const indicator = (ctx) => ctx.indicator.style;
const refusal = (ctx) => ctx.refusal;
const shown = (ctx) => ctx.refusal.style.display === "block";
const reason = (ctx) => ctx.refusal.textContent;

beforeEach(() => {
  document.body.innerHTML = "";
  window.__pbDropHints = null;
  window.__pbDropRefusals = null;

  vi.stubGlobal("requestAnimationFrame", () => 1);
  vi.stubGlobal("cancelAnimationFrame", () => {});

  Object.defineProperty(document.documentElement, "clientHeight", {
    configurable: true,
    get: () => 800,
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

// What the hook feeds the resolver, as plain rectangles: a paragraph that holds children and
// refuses, inside a wrapper that takes the drag.
function lookup(over = {}) {
  const rects = {
    wrapper: { left: 0, right: 300, top: 100, bottom: 500, width: 300, height: 400 },
    paragraph: { left: 0, right: 300, top: 200, bottom: 300, width: 300, height: 100 },
  };
  const parents = { paragraph: "wrapper", wrapper: null };

  return {
    rectOf: (el) => rects[el],
    styleOf: () => ({ display: "block" }),
    parentOf: (el) => parents[el],
    childrenOf: (parent) => (parent === "wrapper" ? ["paragraph"] : ["wrapper"]),
    idOf: (el) => el,
    labelOf: (el) => el,
    accepts: () => true,
    nests: () => false,
    refuses: (el) => el === "paragraph",
    ...over,
  };
}

describe("the line for a box the pointer is aimed into that will not take the drag", () => {
  it("goes right after the box through the whole middle, and says it was moved", () => {
    for (const y of [240, 250, 260]) {
      const target = resolveDrop({ x: 150, y }, "paragraph", lookup());

      expect(target, `at ${y}`).toMatchObject({
        parent_id: "wrapper",
        anchor_id: "paragraph",
        anchor_before: false,
        before: false,
        redirected: true,
        label: "paragraph",
      });
    }
  });

  it("is the plain line in front of or behind it in the outer thirds, where beside is what was aimed at", () => {
    const top = resolveDrop({ x: 150, y: 210 }, "paragraph", lookup());
    const bottom = resolveDrop({ x: 150, y: 290 }, "paragraph", lookup());

    expect(top).toMatchObject({ anchor_before: true, before: true, redirected: false });
    expect(bottom).toMatchObject({ anchor_before: false, before: false, redirected: false });
  });

  it("does not exist until the verdict says the box refuses", () => {
    const target = resolveDrop({ x: 150, y: 240 }, "paragraph", lookup({ refuses: undefined }));

    expect(target).toMatchObject({ anchor_before: true, redirected: false });
  });

  it("and a box that does take it is entered, not refused", () => {
    const target = resolveDrop(
      { x: 150, y: 250 },
      "paragraph",
      lookup({ nests: () => true, refuses: () => false }),
    );

    expect(target).toMatchObject({ inside: true, parent_id: "paragraph" });
  });
});

describe("the canvas, with a form dragged over a paragraph", () => {
  const dt = () => transfer({ [TEMPLATE_MIME]: "<form></form>" });

  // The verdict as the server sends it: the wrapper and the section take a form, the paragraph and
  // its words do not, and only the paragraph — a box — has a reason.
  function verdict(extra = {}) {
    window.__pbDropHints = { nwrapper0: true, nparagrph: false, nwords000: false, nsection0: true };
    window.__pbDropRefusals = { nparagrph: REASON, ...extra };
  }

  it("outlines the paragraph and names the rule, with the no-symbol", () => {
    const { paragraph } = page();
    const ctx = mount(document.getElementById("pb-canvas-root"));
    verdict();

    ctx.onDragOver(at("dragover", paragraph, dt(), 250));

    expect(shown(ctx)).toBe(true);
    expect(reason(ctx)).toBe(REASON);
    expect(refusal(ctx).querySelector(".hero-no-symbol"), "the editor's icon, as a class").not.toBe(
      null,
    );
  });

  it("around the paragraph's own box, grown a little so it reads as fenced off", () => {
    const { paragraph } = page();
    const ctx = mount(document.getElementById("pb-canvas-root"));
    verdict();

    ctx.onDragOver(at("dragover", paragraph, dt(), 250));

    const style = refusal(ctx).style;
    expect(style.transform).toContain("translate3d(-4px, 196px, 0)");
    expect(style.width).toBe("308px");
    expect(style.height).toBe("108px");
  });

  it("while the line goes under the paragraph, where the drop will land", () => {
    const { paragraph } = page();
    const ctx = mount(document.getElementById("pb-canvas-root"));
    verdict();

    // The first half of the middle used to put the line above the paragraph.
    ctx.onDragOver(at("dragover", paragraph, dt(), 240));

    expect(indicator(ctx).transform).toContain(", 300px,");
    expect(ctx.indicator.textContent, "and says which box it went after").toContain("after <p>");
  });

  it("and drops after it", () => {
    const { paragraph } = page();
    const ctx = mount(document.getElementById("pb-canvas-root"));
    verdict();

    ctx.onDragOver(at("dragover", paragraph, dt(), 240));
    ctx.onDrop(at("drop", paragraph, dt(), 240));

    const [, payload] = ctx.pushed.at(-1);
    expect(payload).toMatchObject({ anchor_id: "nparagrph", anchor_before: false });
  });

  it("names the paragraph when the pointer is over its words, which is where it usually is", () => {
    const { words } = page();
    const ctx = mount(document.getElementById("pb-canvas-root"));
    window.__pbDropHints = { nwrapper0: true, nparagrph: false, nwords000: false };
    window.__pbDropRefusals = { nparagrph: REASON };

    // The words refuse too but hold no children, so they have no reason; the paragraph above them
    // is the box the drop climbs out of.
    ctx.onDragOver(at("dragover", words, dt(), 220));

    expect(shown(ctx)).toBe(true);
    expect(reason(ctx)).toBe(REASON);
    expect(refusal(ctx).style.transform).toContain("translate3d(-4px, 196px, 0)");
  });

  it("says nothing over a box that takes the drag", () => {
    const { section } = page();
    const ctx = mount(document.getElementById("pb-canvas-root"));
    verdict();

    ctx.onDragOver(at("dragover", section, dt(), 350));

    expect(shown(ctx)).toBe(false);
  });

  it("says nothing over a box the verdict refused without a reason, such as an image", () => {
    const { paragraph } = page();
    const ctx = mount(document.getElementById("pb-canvas-root"));
    verdict();
    window.__pbDropRefusals = {};

    ctx.onDragOver(at("dragover", paragraph, dt(), 250));

    expect(shown(ctx)).toBe(false);
  });

  it("and nothing before the verdict has arrived, not even from the last drag's reasons", () => {
    const { paragraph } = page();
    const ctx = mount(document.getElementById("pb-canvas-root"));
    window.__pbDropHints = null;
    window.__pbDropRefusals = { nparagrph: REASON };

    ctx.onDragOver(at("dragover", paragraph, dt(), 250));

    expect(shown(ctx)).toBe(false);
  });

  it("appears when the verdict lands under a pointer that is not moving", () => {
    const { paragraph } = page();
    const ctx = mount(document.getElementById("pb-canvas-root"));
    document.elementFromPoint = () => paragraph;
    ctx.dragging = "nmoving00";

    ctx.onDragOver(at("dragover", paragraph, dt(), 250));
    expect(shown(ctx), "the guess offered to go inside").toBe(false);

    ctx.handlers["pb:drop-hints"]({
      accepts: { nwrapper0: true, nparagrph: false },
      refusals: { nparagrph: REASON },
    });

    expect(shown(ctx)).toBe(true);
    expect(reason(ctx)).toBe(REASON);
  });

  it("goes when the pointer moves to a box that takes the drag, leaves, or lets go", () => {
    const { paragraph, section } = page();
    const ctx = mount(document.getElementById("pb-canvas-root"));
    verdict();

    ctx.onDragOver(at("dragover", paragraph, dt(), 250));
    expect(shown(ctx)).toBe(true);
    ctx.onDragOver(at("dragover", section, dt(), 350));
    expect(shown(ctx)).toBe(false);

    ctx.onDragOver(at("dragover", paragraph, dt(), 250));
    expect(shown(ctx)).toBe(true);
    ctx.onDragLeave({ relatedTarget: null });
    expect(shown(ctx)).toBe(false);

    ctx.onDragOver(at("dragover", paragraph, dt(), 250));
    expect(shown(ctx)).toBe(true);
    ctx.onDrop(at("drop", paragraph, dt(), 250));
    expect(shown(ctx)).toBe(false);
  });

  // The chip is above the box; a box at the very top of the page leaves no room for it there.
  it("sits inside the box when there is no room above it", () => {
    const { paragraph } = page(20);
    const ctx = mount(document.getElementById("pb-canvas-root"));
    verdict();

    ctx.onDragOver(at("dragover", paragraph, dt(), 70));

    expect(refusal(ctx).firstChild.style.top).toBe("4px");
  });

  it("and above it when there is", () => {
    const { paragraph } = page(300);
    const ctx = mount(document.getElementById("pb-canvas-root"));
    verdict();

    ctx.onDragOver(at("dragover", paragraph, dt(), 350));

    expect(refusal(ctx).firstChild.style.top).toBe("-26px");
  });

  it("is taken off the page with the hook", () => {
    const { paragraph } = page();
    const ctx = mount(document.getElementById("pb-canvas-root"));
    verdict();
    ctx.onDragOver(at("dragover", paragraph, dt(), 250));

    hooks.PbCanvas.destroyed.call(ctx);

    expect(document.body.contains(ctx.refusal)).toBe(false);
  });
});

// THE REASONS TRAVEL WITH THE VERDICT, to every window the pointer can reach: the chrome's for a
// palette card or a layers row, a frame's for a node picked up on the canvas.
describe("the reasons, spread like the verdict", () => {
  const post = (data) => window.dispatchEvent(new MessageEvent("message", { data, source: {} }));

  function chrome() {
    const el = document.createElement("div");
    const frame = document.createElement("iframe");
    frame.setAttribute("src", "/admin/dashboard/runtime/builder-canvas/tok");
    el.appendChild(frame);
    document.body.appendChild(el);

    const handlers = {};
    const ctx = {
      el,
      handlers,
      pushEvent: () => {},
      handleEvent: (name, fn) => (handlers[name] = fn),
    };
    hooks.PbShortcuts.mounted.call(ctx);
    chromes.push(ctx);
    return { ctx, frame };
  }

  // `PbShortcuts` binds on `window`, so a mount left standing answers every later message as well.
  let chromes = [];

  afterEach(() => {
    window.dispatchEvent(new Event("dragend"));
    for (const ctx of chromes) hooks.PbShortcuts.destroyed?.call(ctx);
    chromes = [];
  });

  it("reach every frame from the chrome, for a drag that began there", () => {
    const { ctx, frame } = chrome();
    const card = document.createElement("div");
    card.dataset.template = "<form></form>";
    document.body.appendChild(card);
    const palette = { el: card, pushEvent: () => {}, handleEvent: () => {} };
    hooks.PbPaletteItem.mounted.call(palette);
    palette.onDragStart({ dataTransfer: { effectAllowed: "", setData: () => {} } });

    ctx.handlers["pb:drop-hints"]({
      accepts: { nparagrph: false },
      refusals: { nparagrph: REASON },
    });

    expect(window.__pbDropRefusals).toEqual({ nparagrph: REASON });
    expect(frame.contentWindow.__pbDropRefusals).toEqual({ nparagrph: REASON });
  });

  it("reach the chrome and the other frames from a frame, by the message it posts", () => {
    const { frame } = chrome();

    post({ pb: true, kind: "hints", accepts: { nparagrph: false }, refusals: { nparagrph: REASON } });

    expect(window.__pbDropRefusals).toEqual({ nparagrph: REASON });
    expect(frame.contentWindow.__pbDropRefusals).toEqual({ nparagrph: REASON });
  });

  it("are kept by a frame that was asked about its own drag", () => {
    page();
    const ctx = mount(document.getElementById("pb-canvas-root"));
    ctx.dragging = "nmoving00";

    ctx.handlers["pb:drop-hints"]({
      accepts: { nparagrph: false },
      refusals: { nparagrph: REASON },
    });

    expect(window.__pbDropRefusals).toEqual({ nparagrph: REASON });
  });

  it("and go when the drag ends, so the next drag never reads them", () => {
    chrome();
    window.__pbDropHints = { nparagrph: false };
    window.__pbDropRefusals = { nparagrph: REASON };

    post({ pb: true, kind: "dragend" });

    expect(window.__pbDropHints).toBe(null);
    expect(window.__pbDropRefusals).toBe(null);
  });
});
