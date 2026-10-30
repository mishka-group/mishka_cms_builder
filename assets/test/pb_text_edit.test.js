// SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
//
// SPDX-License-Identifier: Apache-2.0

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import hooks from "../js/index.js";

// WORDS OPEN FOR EDITING STAY OPEN, AND STAY THE AUTHOR'S.
//
// A double click opens a run of text in the canvas for typing. Three things went wrong in an e2e
// run building a landing page, and each is pinned here: the next LiveView patch took the words back
// (and with them the caret, so the keys meant for them reached the editor's shortcuts), the caret
// opened at the start of the words so a new title went in front of the old one, and ⌘A was left to
// a browser that did not always keep it inside them.
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

describe("words open for editing", () => {
  // LiveView keeps what it did not render on an element marked `phx-update="ignore"`, and leaves its
  // children alone; without it, the next patch took `contenteditable` off and blurred the words.
  it("are kept out of LiveView's patches while they are open", () => {
    canvas(PAGE);

    doubleClick($("#words"));

    expect($("#words").getAttribute("contenteditable")).toBe("plaintext-only");
    expect($("#words").getAttribute("phx-update")).toBe("ignore");
  });

  it("are written back under the id that was opened, and handed back to LiveView", () => {
    const ctx = canvas(PAGE);

    doubleClick($("#words"));
    $("#words").textContent = "Pricing";
    // A patch is free to merge `data-*` onto an ignored element.
    $("#words").dataset.nodeId = "somebody-else";
    $("#words").dispatchEvent(new FocusEvent("blur"));

    expect(ctx.pushed.at(-1)).toEqual(["set_text", { id: "t1", text: "Pricing", pre: false }]);
    expect($("#words").hasAttribute("contenteditable")).toBe(false);
    expect($("#words").hasAttribute("phx-update")).toBe(false);
  });

  // The first click's own `select` re-renders the frame, and a redraw can replace the element the
  // double click began on.
  it("are the live element, when the one pressed was redrawn before the double click", () => {
    canvas(PAGE);

    const pressed = $("#words");
    click(pressed, 1);
    click(pressed, 2);

    const redrawn = pressed.cloneNode(true);
    pressed.replaceWith(redrawn);
    redrawn.dispatchEvent(new MouseEvent("dblclick", { bubbles: true, cancelable: true, detail: 2 }));

    expect(redrawn.getAttribute("contenteditable")).toBe("plaintext-only");
  });

  // Escape leaves the words and keeps the element: the editor's own Escape, which drops the
  // selection, never hears it.
  it("let Escape put them down without also dropping the selection", () => {
    canvas(PAGE);

    doubleClick($("#words"));
    key($("#words"), { key: "Escape", code: "Escape" });
    $("#words").dispatchEvent(new FocusEvent("blur"));

    expect(shortcuts(posted)).toEqual([]);
    expect($("#words").hasAttribute("contenteditable")).toBe(false);
  });

  // There a double click selects a word, which is the browser's; opening the words a second time
  // stacked a second set of listeners and wrote them back twice.
  it("are left to the browser by a double click inside them", () => {
    const ctx = canvas(PAGE);

    doubleClick($("#words"));
    doubleClick($("#words"));
    $("#words").dispatchEvent(new FocusEvent("blur"));

    expect(ctx.pushed.filter(([name]) => name === "set_text")).toEqual([
      ["set_text", { id: "t1", text: "Heading", pre: false }],
    ]);
  });

  // The template's newline and indentation ride along in `textContent`. Whether they are on screen
  // is the element's to say, and the server keeps them only when they are. Asked before the words
  // open: Chrome draws an open `plaintext-only` run `pre-wrap`.
  it("say whether their element keeps its line breaks", () => {
    // On the run itself: jsdom does not inherit `white-space` from the parent, a browser does.
    const ctx = canvas(
      '<div data-node-id="p1" data-kind="tag">' +
        '<span id="pre-words" data-node-id="t2" data-kind="text" style="white-space:pre-line">' +
        "one\n  two</span></div>" +
        PAGE,
    );

    doubleClick($("#pre-words"));
    $("#pre-words").dispatchEvent(new FocusEvent("blur"));
    doubleClick($("#words"));
    $("#words").dispatchEvent(new FocusEvent("blur"));

    expect(ctx.pushed.filter(([name]) => name === "set_text")).toEqual([
      ["set_text", { id: "t2", text: "one\n  two", pre: true }],
      ["set_text", { id: "t1", text: "Heading", pre: false }],
    ]);
  });

  it("as the element was drawn before they opened", () => {
    const ctx = canvas(PAGE);

    const drawn = window.getComputedStyle;
    vi.spyOn(window, "getComputedStyle").mockImplementation((el, pseudo) => {
      const style = drawn.call(window, el, pseudo);
      if (!el.hasAttribute?.("contenteditable")) return style;
      return { ...style, whiteSpace: "pre-wrap", whiteSpaceCollapse: "preserve" };
    });

    doubleClick($("#words"));
    $("#words").dispatchEvent(new FocusEvent("blur"));

    expect(ctx.pushed.at(-1)).toEqual(["set_text", { id: "t1", text: "Heading", pre: false }]);
  });

  it("take ⌘A as their own words and nothing around them", () => {
    canvas(`<p data-node-id="p0" data-kind="tag">Before</p>${PAGE}`);

    doubleClick($("#words"));
    const event = key($("#words"), { key: "a", code: "KeyA", metaKey: true });

    expect(event.defaultPrevented).toBe(true);
    expect(String(document.getSelection())).toBe("Heading");
    expect($("#words").contains(document.getSelection().getRangeAt(0).commonAncestorContainer)).toBe(
      true,
    );
  });

  it("and Ctrl+A the same, on any layout", () => {
    canvas(PAGE);

    doubleClick($("#words"));
    const event = key($("#words"), { key: "ф", code: "KeyA", ctrlKey: true });

    expect(event.defaultPrevented).toBe(true);
    expect(String(document.getSelection())).toBe("Heading");
  });

  // `focus()` puts the caret at the start, so what was typed went in front of the old words.
  it("open with the caret where the double click was", () => {
    canvas(PAGE);

    document.caretRangeFromPoint = () => {
      const range = document.createRange();
      range.setStart($("#words").firstChild, 4);
      range.collapse(true);
      return range;
    };

    doubleClick($("#words"));

    const selection = document.getSelection();
    expect(selection.anchorNode).toBe($("#words").firstChild);
    expect(selection.anchorOffset).toBe(4);
  });

  // An e2e run double-clicked "Build", pressed ⌘End and typed: the browser had not moved the caret,
  // and the words went in after "Bui". The ends of the run are answered by the editor itself.
  describe("go to the ends of their own words", () => {
    // Written on its own line of the template, as a hero's heading is: a newline and indentation on
    // each side of the words, which the page does not draw.
    const WORDS = "\n      Build the site\n    ";
    const FIRST = 7;
    const LAST = 21;

    const LONG =
      '<p data-node-id="p0" data-kind="tag">Before</p>' +
      '<h1 data-node-id="h1" data-kind="tag">' +
      `<span id="words" data-node-id="t1" data-kind="text">${WORDS}</span></h1>` +
      '<p data-node-id="p2" data-kind="tag">After</p>';

    const caretIn = (offset) => {
      const range = document.createRange();
      range.setStart($("#words").firstChild, offset);
      range.collapse(true);
      document.getSelection().removeAllRanges();
      document.getSelection().addRange(range);
    };

    const at = () => {
      const selection = document.getSelection();

      return {
        node: selection.focusNode,
        offset: selection.focusOffset,
        collapsed: selection.isCollapsed,
        text: String(selection),
      };
    };

    for (const [name, init, offset] of [
      ["⌘↓", { key: "ArrowDown", code: "ArrowDown", metaKey: true }, LAST],
      ["⌘End", { key: "End", code: "End", metaKey: true }, LAST],
      ["Ctrl+End", { key: "End", code: "End", ctrlKey: true }, LAST],
      ["⌘↑", { key: "ArrowUp", code: "ArrowUp", metaKey: true }, FIRST],
      ["⌘Home", { key: "Home", code: "Home", metaKey: true }, FIRST],
      ["Ctrl+Home", { key: "Home", code: "Home", ctrlKey: true }, FIRST],
    ]) {
      it(`${name} goes to the ${offset === LAST ? "last" : "first"} word`, () => {
        canvas(LONG);
        doubleClick($("#words"));
        caretIn(10);

        const event = key($("#words"), init);

        expect(event.defaultPrevented).toBe(true);
        expect(at()).toEqual({
          node: $("#words").firstChild,
          offset,
          collapsed: true,
          text: "",
        });
        expect(shortcuts(posted)).toEqual([]);
      });
    }

    // Chrome draws an open `plaintext-only` run `pre-wrap`; the page does not.
    it("as the page draws them, not as the open run is drawn", () => {
      const drawn = window.getComputedStyle;
      vi.spyOn(window, "getComputedStyle").mockImplementation((el, pseudo) => {
        const style = drawn.call(window, el, pseudo);
        if (!el.hasAttribute?.("contenteditable")) return style;
        return { ...style, whiteSpace: "pre-wrap", whiteSpaceCollapse: "preserve" };
      });

      canvas(LONG);
      doubleClick($("#words"));
      caretIn(10);

      key($("#words"), { key: "End", code: "End", metaKey: true });
      expect(at().offset).toBe(LAST);
    });

    it("and Shift carries the selection with it", () => {
      canvas(LONG);
      doubleClick($("#words"));
      caretIn(13);

      key($("#words"), { key: "End", code: "End", metaKey: true, shiftKey: true });
      expect(at().text).toBe("the site");

      caretIn(12);
      key($("#words"), { key: "ArrowUp", code: "ArrowUp", metaKey: true, shiftKey: true });
      expect(at().text).toBe("Build");
    });

    // A `<pre>`'s line breaks are on screen, so they are part of its words.
    it("which, where line breaks show, are the run's own ends", () => {
      canvas(
        '<pre data-node-id="p1" data-kind="tag">' +
          '<span id="words" data-node-id="t1" data-kind="text" style="white-space:pre">' +
          "one\n  two\n</span></pre>",
      );
      doubleClick($("#words"));
      caretIn(2);

      key($("#words"), { key: "End", code: "End", metaKey: true });
      expect(at().offset).toBe(10);
    });

    // The line's own ends, a word at a time and a paragraph at a time stay the browser's.
    it("and leaves End, ⌥↓ and Ctrl+↓ to the browser", () => {
      canvas(LONG);
      doubleClick($("#words"));

      for (const init of [
        { key: "End", code: "End" },
        { key: "ArrowDown", code: "ArrowDown", altKey: true },
        { key: "ArrowDown", code: "ArrowDown", ctrlKey: true },
      ]) {
        expect(key($("#words"), init).defaultPrevented).toBe(false);
      }
    });
  });

  // Chrome stops answering once the words are open: every point inside the canvas's unselectable
  // run then reads as its first position, and an e2e run's words went in ahead of the heading.
  it("asking where the pointer was before the words are open", () => {
    canvas(PAGE);

    document.caretRangeFromPoint = () => {
      const range = document.createRange();
      const open = $("#words").hasAttribute("contenteditable");
      range.setStart($("#words").firstChild, open ? 0 : 4);
      range.collapse(true);
      return range;
    };

    doubleClick($("#words"));

    expect(document.getSelection().anchorOffset).toBe(4);
  });

  it("and at the end when the browser cannot say where the pointer was", () => {
    canvas(PAGE);

    doubleClick($("#words"));

    const range = document.getSelection().getRangeAt(0);
    const end = document.createRange();
    end.selectNodeContents($("#words"));
    end.collapse(false);

    expect(range.collapsed).toBe(true);
    expect(range.compareBoundaryPoints(Range.START_TO_START, end)).toBe(0);
  });
});
