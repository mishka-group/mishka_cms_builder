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

  // A link's click is answered by its own capture handler, which stops the page from following it;
  // the ring moved only when the server answered, so a key pressed before then named the element
  // ringed before. A navbar link is where the e2e run lost its "Home".
  it("names a link the moment it is clicked", () => {
    canvas(
      '<nav data-node-id="n1" data-kind="tag"><a id="home" href="/" data-node-id="a1" data-kind="tag">' +
        '<span id="home-words" data-node-id="t2" data-kind="text">Home</span></a></nav>' +
        PAGE,
    );

    click($("#words"));
    click($("#home-words"));
    backspace();

    expect(shortcuts(posted)[0]).toMatchObject({ key: "delete", node_id: "a1" });
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

// THE ELEMENT TOOLBAR IS THE SERVER'S SELECTION, DRAWN WHERE THE RING IS. For the round trip after a
// click it sits on the new element and still names, and deletes, the old one.
describe("the element toolbar", () => {
  const toolbar =
    '<div id="pb-el-toolbar"><button id="pb-eltb-delete" type="button" phx-click="toolbar" phx-value-action="delete">x</button></div>';

  let heard;

  beforeEach(() => {
    // Where LiveView listens for `phx-click`: a click that reaches this would press the button.
    heard = vi.fn();
    window.addEventListener("click", heard);
  });

  afterEach(() => window.removeEventListener("click", heard));

  it("does nothing while it still names the element selected before", () => {
    const ctx = canvas(PAGE + toolbar);
    ctx.el.dataset.selection = "s1";

    click($("#words"));
    heard.mockClear();
    const event = new MouseEvent("click", { bubbles: true, cancelable: true, detail: 1 });
    $("#pb-eltb-delete").dispatchEvent(event);

    expect(event.defaultPrevented).toBe(true);
    expect(heard).not.toHaveBeenCalled();
  });

  it("and acts once it names the ringed one", () => {
    const ctx = canvas(PAGE + toolbar);

    click($("#words"));
    ctx.el.dataset.selection = "h1";
    heard.mockClear();
    click($("#pb-eltb-delete"));

    expect(heard).toHaveBeenCalledTimes(1);
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

// ⌘Z WHILE TYPING TAKES BACK THE TYPING. Inline words are written to the document by `set_text` on
// blur, so until then they are a pending edit in the DOM. ⌘Z sent to the server undid the
// structural change before them, a block dropped a minute earlier, while the words stayed on screen.
// In typed text undo and redo are the field's own: the browser's, or CodeMirror's in the Code
// window. Anywhere else they still undo the page.
describe("undo while typing", () => {
  const undo = (target) => key(target, { metaKey: true, key: "z", code: "KeyZ" });
  const redo = (target) => key(target, { metaKey: true, shiftKey: true, key: "z", code: "KeyZ" });

  // jsdom has no `isContentEditable`; this is the browser's answer: inside an editing host.
  beforeEach(() => {
    Object.defineProperty(HTMLElement.prototype, "isContentEditable", {
      configurable: true,
      get() {
        const host = this.closest("[contenteditable]");
        return host !== null && host.getAttribute("contenteditable") !== "false";
      },
    });
  });

  afterEach(() => {
    delete HTMLElement.prototype.isContentEditable;
  });

  describe("on the canvas", () => {
    it("is the browser's while words are open for typing", () => {
      canvas(PAGE);

      doubleClick($("#words"));
      const back = undo($("#words"));
      const again = redo($("#words"));

      expect(shortcuts(posted)).toEqual([]);
      expect(back.defaultPrevented).toBe(false);
      expect(again.defaultPrevented).toBe(false);
    });

    it("and the page's once they are put down", () => {
      canvas(PAGE);

      doubleClick($("#words"));
      $("#words").dispatchEvent(new FocusEvent("blur"));
      const back = undo(document.body);

      expect(shortcuts(posted)).toHaveLength(1);
      expect(shortcuts(posted)[0]).toMatchObject({ key: "undo", node_id: "h1" });
      expect(back.defaultPrevented).toBe(true);
    });
  });

  describe("in the chrome", () => {
    const fields =
      '<input id="text" type="text" /><textarea id="area"></textarea>' +
      '<div id="cm" class="cm-content" contenteditable="true"></div>' +
      '<select id="pick"><option>a</option></select><input id="tick" type="checkbox" />';

    it("is the field's own in a text input, a textarea and the Code window's editor", () => {
      const ctx = chrome("h1");
      document.body.insertAdjacentHTML("beforeend", fields);

      const keys = ["#text", "#area", "#cm"].flatMap((id) => [undo($(id)), redo($(id))]);

      expect(ctx.pushed).toEqual([]);
      expect(keys.map((event) => event.defaultPrevented)).toEqual(keys.map(() => false));
    });

    it("and the page's in a field with no typed text of its own", () => {
      const ctx = chrome("h1");
      document.body.insertAdjacentHTML("beforeend", fields);

      undo($("#pick"));
      redo($("#tick"));

      expect(ctx.pushed).toEqual([
        ["shortcut", { key: "undo", node_id: "h1" }],
        ["shortcut", { key: "redo", node_id: "h1" }],
      ]);
    });

    it("and the page's with the focus outside every field", () => {
      const ctx = chrome("h1");

      const back = undo(document.body);

      expect(ctx.pushed).toEqual([["shortcut", { key: "undo", node_id: "h1" }]]);
      expect(back.defaultPrevented).toBe(true);
    });
  });
});
