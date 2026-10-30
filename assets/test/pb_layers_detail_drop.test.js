// SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
//
// SPDX-License-Identifier: Apache-2.0

import { afterEach, beforeEach, describe, expect, it } from "vitest";
import hooks from "../js/index.js";

// A DROP ON A COMPONENT'S DETAILS.
//
// Between a component's row and its slots the layers rail draws the component's own `.properties`,
// `.slots` and `.markup` groups. On a landing page's navbar those are most of what sits between the
// navbar and the next section, and none of them was a target: a section dragged to just under the
// navbar was released over `.properties` and nothing happened, with no word about why. Reordering
// was left to Cut and Paste after.
//
// They belong to the component, so they answer as its row: the pointer is below that row's box, the
// row is marked "after", and the drop lands after the component.
const NODE_MIME = "application/x-pb-node";

function transfer(entries = {}) {
  const data = { ...entries };

  return {
    get types() {
      return Object.keys(data);
    },
    effectAllowed: "move",
    dropEffect: "none",
    setData: (type, value) => (data[type] = value),
    getData: (type) => data[type] || "",
  };
}

function dragEvent(type, target, dataTransfer, clientY) {
  const event = {
    type,
    target,
    dataTransfer,
    clientX: 10,
    clientY,
    defaultPrevented: false,
    preventDefault() {
      event.defaultPrevented = true;
    },
    stopPropagation: () => {},
    relatedTarget: null,
  };

  return event;
}

let mounted = [];

function mount(el) {
  const pushed = [];
  const ctx = { el, pushed, pushEvent: (name, payload) => pushed.push([name, payload]) };
  ctx.handleEvent = () => {};
  hooks.PbLayers.mounted.call(ctx);
  mounted.push(ctx);
  return ctx;
}

const box = (top, height = 20) => () => ({
  top,
  bottom: top + height,
  height,
  left: 0,
  right: 200,
  width: 200,
});

// The rail as `Panels.layer_row/1` draws it: every node a `[data-layer-id]` wrapper holding its own
// row, then — for a component — its detail groups, then its children's wrappers.
function rail() {
  const el = document.createElement("div");
  el.getBoundingClientRect = () => ({ top: 0, bottom: 400, height: 400, left: 0, right: 200, width: 200 });
  document.body.appendChild(el);

  const wrapper = (id, { parentId = "root", index, top, kind = "tag" }) => {
    const wrap = document.createElement("div");
    wrap.dataset.layerId = id;

    const row = document.createElement("div");
    row.dataset.layerRow = id;
    row.dataset.parentId = parentId;
    row.dataset.index = String(index);
    row.dataset.container = "true";
    row.dataset.kind = kind;
    row.dataset.open = "true";
    row.getBoundingClientRect = box(top);
    wrap.appendChild(row);

    el.appendChild(wrap);
    return { wrap, row };
  };

  const navbar = wrapper("nnavbar00", { index: 0, top: 0, kind: "component" });

  // `.properties`, `.slots`, `.markup`: buttons with no row of their own.
  const details = ["props", "slots", "markup"].map((name, at) => {
    const group = document.createElement("div");
    const button = document.createElement("button");
    button.id = `pb-${name}-nnavbar00`;
    button.textContent = `.${name}`;
    button.getBoundingClientRect = box(20 + at * 20);
    group.appendChild(button);
    navbar.wrap.appendChild(group);
    return button;
  });

  const section = wrapper("nsection0", { index: 1, top: 80 });

  return { el, navbar, details, section };
}

beforeEach(() => {
  document.body.innerHTML = "";
  window.__pbDropHints = null;
  window.__pbDragNode = null;
  if (!window.CSS) window.CSS = {};
  if (!window.CSS.escape) window.CSS.escape = (value) => String(value);
});

afterEach(() => {
  window.dispatchEvent(new Event("dragend"));
  for (const ctx of mounted) hooks.PbLayers.destroyed.call(ctx);
  mounted = [];
});

describe("a row dragged over a component's own details", () => {
  it("is taken, and the component's row says the drop goes after it", () => {
    const { el, navbar, details, section } = rail();
    const ctx = mount(el);
    const dt = transfer();

    ctx.onDragStart(dragEvent("dragstart", section.row, dt, 85));

    const over = dragEvent("dragover", details[0], dt, 30);
    ctx.onDragOver(over);

    expect(over.defaultPrevented, "the browser is told this is a place to drop").toBe(true);
    expect(navbar.row.dataset.drop).toBe("after");
  });

  it("and lands after the component, beside it rather than in it", () => {
    const { el, details, section } = rail();
    const ctx = mount(el);
    const dt = transfer();

    ctx.onDragStart(dragEvent("dragstart", section.row, dt, 85));
    ctx.onDragOver(dragEvent("dragover", details[1], dt, 50));
    ctx.onDrop(dragEvent("drop", details[1], dt, 50));

    const [name, payload] = ctx.pushed.at(-1);
    expect(name).toBe("drop");
    expect(payload).toMatchObject({ node_id: "nsection0", parent_id: "root", index: 1 });
  });

  it("from the canvas as well, where the id arrives on the dataTransfer", () => {
    const { el, details } = rail();
    const ctx = mount(el);
    const dt = transfer({ [NODE_MIME]: "ncanvas00" });

    ctx.onDrop(dragEvent("drop", details[2], dt, 70));

    const [, payload] = ctx.pushed.at(-1);
    expect(payload).toMatchObject({ node_id: "ncanvas00", parent_id: "root", index: 1 });
  });

  it("but not over the dragged component's own details", () => {
    const { el, navbar, details } = rail();
    const ctx = mount(el);
    const dt = transfer();

    ctx.onDragStart(dragEvent("dragstart", navbar.row, dt, 5));

    const over = dragEvent("dragover", details[0], dt, 30);
    ctx.onDragOver(over);
    ctx.onDrop(dragEvent("drop", details[0], dt, 30));

    expect(navbar.row.dataset.drop).toBeUndefined();
    expect(ctx.pushed.filter(([name]) => name === "drop")).toHaveLength(0);
  });

  it("and the rail's own heading, outside every row, still takes nothing", () => {
    const { el, section } = rail();
    const ctx = mount(el);
    const dt = transfer();
    const heading = document.createElement("div");
    el.prepend(heading);

    ctx.onDragStart(dragEvent("dragstart", section.row, dt, 85));

    const over = dragEvent("dragover", heading, dt, 2);
    ctx.onDragOver(over);

    expect(over.defaultPrevented).toBe(false);
  });
});
