// SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
//
// SPDX-License-Identifier: Apache-2.0

import { afterEach, describe, expect, it } from "vitest";
import { drawsNothing, markBlanks } from "../js/hooks.js";

// A COMPONENT THAT DRAWS NOTHING IS STILL A NODE ON THE PAGE. A pager with one page, a card handed no
// post or a flash group pinned to the viewport left its box at zero pixels, and the canvas had nothing
// to select. jsdom does no layout, so each element's box is given here: what is asserted is which
// boxes the hook marks for the floor `#pb-canvas-chrome` draws.
function sized(el, width, height) {
  el.getBoundingClientRect = () => ({ width, height, top: 0, left: 0, right: width, bottom: height });
  return el;
}

function frame(inner, { attrs = "" } = {}) {
  document.body.innerHTML = `<div id="root"><div data-pb-frame="true" data-node-id="n1" data-kind="component" data-component="blog-pager" ${attrs}>${inner}</div></div>`;
  return document.querySelector("[data-node-id]");
}

afterEach(() => {
  document.body.innerHTML = "";
});

describe("drawsNothing", () => {
  it("is true of a box with nothing in it but comments and indentation", () => {
    const el = frame("<!-- a component's annotation -->\n   \n");
    expect(drawsNothing(el)).toBe(true);
  });

  it("is true when every element inside has no size", () => {
    const el = frame('<div class="w-full"></div><nav></nav>');
    for (const child of el.children) sized(child, 866, 0);
    expect(drawsNothing(el)).toBe(true);
  });

  it("is false once one element inside has a box, however thin", () => {
    const el = frame('<div role="separator"></div><div></div>');
    sized(el.children[0], 866, 1);
    sized(el.children[1], 0, 0);
    expect(drawsNothing(el)).toBe(false);
  });

  it("is false for words written straight into the box", () => {
    expect(drawsNothing(frame("Pick a post"))).toBe(false);
  });

  // THE FLOOR MUST NOT TAKE ITSELF OFF. A floored box measures 44px, so asking the box itself would
  // unmark it on the next patch and mark it again on the one after.
  it("asks the content, not the box, so a floored box stays floored", () => {
    const el = sized(frame('<div></div>', { attrs: 'data-pb-blank="true"' }), 866, 44);
    sized(el.children[0], 866, 0);
    expect(drawsNothing(el)).toBe(true);
  });
});

describe("markBlanks", () => {
  it("marks an empty box and unmarks it once something inside it has a size", () => {
    const el = frame("<div></div>");
    const child = sized(el.children[0], 866, 0);

    markBlanks(document.getElementById("root"));
    expect(el.getAttribute("data-pb-blank")).toBe("true");

    sized(child, 866, 120);
    markBlanks(document.getElementById("root"));
    expect(el.hasAttribute("data-pb-blank")).toBe(false);
  });

  it("leaves alone a placeholder that already says what it wants", () => {
    for (const attrs of ['data-pb-overlay="dialog"', 'data-wants-media="src"', 'data-incomplete="true"']) {
      const el = frame("", { attrs });
      markBlanks(document.getElementById("root"));
      expect(el.hasAttribute("data-pb-blank"), attrs).toBe(false);
    }
  });

  it("measures only the editor's own boxes, never a stamped root", () => {
    document.body.innerHTML =
      '<div id="root"><table><tbody><tr data-node-id="n2" data-kind="component"></tr></tbody></table></div>';
    markBlanks(document.getElementById("root"));
    expect(document.querySelector("tr").hasAttribute("data-pb-blank")).toBe(false);
  });
});
