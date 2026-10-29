// SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
//
// SPDX-License-Identifier: Apache-2.0

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import hooks from "../js/index.js";

// TYPING MUST STAY TYPING, AND A KEY ACTS ON WHAT THE AUTHOR CAN SEE.
//
// An e2e run building a landing page double-clicked a heading in a three-column block, saw no caret,
// and pressed Backspace to clear the words. The heading went, then the call-to-action section, then
// the footer, then the hero. Two of the things that made that possible are pinned here (the third,
// the words being taken back by a patch, is `pb_text_edit.test.js`):
//
//   * a Backspace that reaches the page deletes the selected element, even right after a double
//     click that the author took for "I am typing now";
//   * the key carried no word of WHICH element the author saw selected, so the server deleted the
//     one it still held, which under load was the one before.
const live = [];

function canvas(html) {
  document.body.innerHTML = `<div id="pb-canvas-root">${html}</div>`;
  const el = document.getElementById("pb-canvas-root");
  el.dataset.preview = "false";

  const ctx = {
    el,
    pushed: [],
    pushEvent(name, payload) {
      this.pushed.push([name, payload]);
    },
    handleEvent: () => {},
  };

  hooks.PbCanvas.mounted.call(ctx);
  live.push([hooks.PbCanvas, ctx]);
  return ctx;
}

function chrome(selection) {
  const el = document.createElement("div");
  el.id = "pb-root";
  if (selection) el.dataset.selection = selection;
  document.body.appendChild(el);

  const ctx = {
    el,
    pushed: [],
    pushEvent(name, payload) {
      this.pushed.push([name, payload]);
    },
    handleEvent: () => {},
  };

  hooks.PbShortcuts.mounted.call(ctx);
  live.push([hooks.PbShortcuts, ctx]);
  return ctx;
}

const $ = (selector) => document.querySelector(selector);

function click(el, detail = 1) {
  el.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, detail }));
}

// What a real double click is: two presses, then the `dblclick`.
function doubleClick(el) {
  click(el, 1);
  click(el, 2);
  el.dispatchEvent(new MouseEvent("dblclick", { bubbles: true, cancelable: true, detail: 2 }));
}

function key(target, init) {
  const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, ...init });
  target.dispatchEvent(event);
  return event;
}

const backspace = (target = document.body) => key(target, { key: "Backspace", code: "Backspace" });

const shortcuts = (posted) => posted.filter((message) => message.kind === "shortcut");

const PAGE =
  '<section id="band" data-node-id="s1" data-kind="tag" style="padding:40px">' +
  '<h3 id="heading" data-node-id="h1" data-kind="tag">' +
  '<span id="words" data-node-id="t1" data-kind="text">Heading</span>' +
  "</h3></section>";

let posted;

beforeEach(() => {
  document.body.innerHTML = "";
  posted = [];
  vi.stubGlobal("requestAnimationFrame", (fn) => fn(0));
  vi.stubGlobal("CSS", { escape: (value) => value });
  Element.prototype.scrollIntoView = vi.fn();
  vi.spyOn(window.parent, "postMessage").mockImplementation((message) => posted.push(message));
});

afterEach(() => {
  while (live.length) {
    const [hook, ctx] = live.pop();
    hook.destroyed.call(ctx);
  }

  delete document.caretRangeFromPoint;
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe("a key carries the element the author can see", () => {
  it("names the ringed element with every shortcut it posts", () => {
    canvas(PAGE);

    click($("#words"));
    backspace();

    expect(shortcuts(posted)).toEqual([
      { pb: true, kind: "shortcut", key: "delete", node_id: "h1", typing: false },
    ]);
  });

  it("names nothing when nothing is ringed", () => {
    canvas(PAGE);

    backspace();

    expect(shortcuts(posted)[0]).toMatchObject({ key: "delete", node_id: null });
  });

  // The chrome forwards what the frame saw, and names its own selection for a key pressed out here.
  it("is passed on by the chrome, and the chrome names its own for its own keys", () => {
    const ctx = chrome("h1");

    window.dispatchEvent(
      new MessageEvent("message", {
        data: { pb: true, kind: "shortcut", key: "delete", node_id: "t9", typing: true },
        source: {},
      }),
    );
    backspace();

    expect(ctx.pushed).toEqual([
      ["shortcut", { key: "delete", node_id: "t9", typing: true }],
      ["shortcut", { key: "delete", node_id: "h1" }],
    ]);
  });
});

describe("a double click is the author saying they are about to type", () => {
  // Where the e2e run's sections went: the heading had gone, the section below moved up under the
  // pointer, and the double click meant for the heading's words landed on its padding.
  it("so a Backspace after one that opened no words says so instead of deleting", () => {
    canvas(PAGE);

    doubleClick($("#band"));
    backspace();

    expect(shortcuts(posted)).toEqual([
      { pb: true, kind: "shortcut", key: "delete", node_id: "s1", typing: true },
    ]);
  });

  it("and so does one pressed after the open words were taken away", () => {
    canvas(PAGE);

    doubleClick($("#words"));
    $("#words").remove();
    backspace();

    expect(shortcuts(posted)[0]).toMatchObject({ key: "delete", typing: true });
  });

  it("until a single click makes a new choice", () => {
    canvas(PAGE);

    doubleClick($("#band"));
    click($("#band"));
    backspace();

    expect(shortcuts(posted)[0]).toMatchObject({ key: "delete", node_id: "s1", typing: false });
  });

  it("or Enter puts the words down", () => {
    canvas(PAGE);

    doubleClick($("#words"));
    key($("#words"), { key: "Enter", code: "Enter" });
    $("#words").dispatchEvent(new FocusEvent("blur"));
    backspace();

    expect(shortcuts(posted)[0]).toMatchObject({ key: "delete", node_id: "h1", typing: false });
  });

  it("or Escape does", () => {
    canvas(PAGE);

    doubleClick($("#words"));
    key($("#words"), { key: "Escape", code: "Escape" });
    $("#words").dispatchEvent(new FocusEvent("blur"));
    backspace();

    expect(shortcuts(posted)[0]).toMatchObject({ key: "delete", node_id: "h1", typing: false });
  });
});
