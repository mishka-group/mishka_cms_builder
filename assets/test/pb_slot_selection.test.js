// SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
//
// SPDX-License-Identifier: Apache-2.0

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import hooks from "../js/index.js";

// A SLOT IS RINGED ON THE ELEMENT IT BELONGS TO.
//
// A component draws its slots inside its own markup, so a sidebar's `<:item>` selected in the layers
// rail has no `[data-node-id]` on the canvas. The hook painted `data-selected` on nothing, and the
// `[data-pb-overlay]:has([data-selected="true"])` rules that keep an opened overlay in the flow let
// go of it: the sidebar snapped back to `fixed` and the height of the screen. The server sends the
// nearest drawn ancestor with the selection, and the hook paints that one instead.
const live = [];

const PAGE =
  '<div id="sidebar" data-node-id="sb" data-kind="component" data-pb-overlay="drawer">' +
  '<nav class="fixed h-screen"><a href="#">Home</a></nav></div>' +
  '<h1 id="heading" data-node-id="h1" data-kind="tag">Title</h1>';

function canvas(html, root = {}) {
  document.body.innerHTML = `<div id="pb-canvas-root">${html}</div>`;
  const el = document.getElementById("pb-canvas-root");
  el.dataset.preview = "false";
  Object.assign(el.dataset, root);

  const ctx = {
    el,
    handlers: {},
    pushEvent: () => {},
    handleEvent(name, fn) {
      this.handlers[name] = fn;
    },
  };

  hooks.PbCanvas.mounted.call(ctx);
  live.push(ctx);
  return ctx;
}

const ringed = () =>
  [...document.querySelectorAll('[data-selected="true"]')].map((el) => el.dataset.nodeId);

const opened = () => document.querySelector('[data-pb-overlay][data-selected="true"]') !== null;

beforeEach(() => {
  document.body.innerHTML = "";
  vi.stubGlobal("requestAnimationFrame", (fn) => fn(0));
  vi.stubGlobal("CSS", { escape: (value) => value });
  Element.prototype.scrollIntoView = vi.fn();
});

afterEach(() => {
  while (live.length) hooks.PbCanvas.destroyed.call(live.pop());
  vi.unstubAllGlobals();
});

describe("a selection with no element of its own", () => {
  it("rings the anchor the server sends with it, so the overlay stays open", () => {
    const ctx = canvas(PAGE);

    ctx.handlers["pb:selected"]({ id: "nslot0001", anchor: "sb" });

    expect(ringed()).toEqual(["sb"]);
    expect(opened()).toBe(true);
    // The selection is still the slot: a key pressed now names it, not the sidebar.
    expect(ctx.selectedId).toBe("nslot0001");
  });

  it("keeps the anchor ringed across a patch", () => {
    const ctx = canvas(PAGE);

    ctx.handlers["pb:selected"]({ id: "nslot0001", anchor: "sb" });
    document.getElementById("sidebar").removeAttribute("data-selected");
    hooks.PbCanvas.updated.call(ctx);

    expect(ringed()).toEqual(["sb"]);
  });

  it("is handed over on mount, like the selection itself", () => {
    canvas(PAGE, { selection: "nslot0001", selectionAnchor: "sb" });

    expect(ringed()).toEqual(["sb"]);
  });

  it("rings nothing when there is no anchor either", () => {
    const ctx = canvas(PAGE);

    ctx.handlers["pb:selected"]({ id: "nslot0001", anchor: null });

    expect(ringed()).toEqual([]);
  });
});

describe("a selection that is drawn", () => {
  it("is ringed itself, whatever anchor arrives with it", () => {
    const ctx = canvas(PAGE);

    ctx.handlers["pb:selected"]({ id: "h1", anchor: "sb" });

    expect(ringed()).toEqual(["h1"]);
  });

  it("takes the ring off the anchor of the slot selected before it", () => {
    const ctx = canvas(PAGE);

    ctx.handlers["pb:selected"]({ id: "nslot0001", anchor: "sb" });
    document.getElementById("heading").click();
    hooks.PbCanvas.updated.call(ctx);

    expect(ringed()).toEqual(["h1"]);
    expect(opened()).toBe(false);
  });
});
