// SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
//
// SPDX-License-Identifier: Apache-2.0

import { afterEach, beforeEach, describe, expect, it } from "vitest";
import hooks from "../js/index.js";

// ESCAPE IN AN OPEN MODAL HAS ONE OWNER, AND IT IS THE MODAL.
//
// The Code window, Find, the reload and leave questions, Examples, Settings and the new-folder form
// each close on their own `phx-window-keydown`. The keyboard hook on `#pb-root` pushed `shortcut`
// escape for the same press, and its push locks `#pb-root`: LiveView then patched the modal's
// removal into a detached copy of the locked tree. The dialog faded, its full-screen backdrop
// stayed, and every click in the editor landed on it until a reload. The server half, that each of
// those modals carries the mark, is `keyboard_test.exs`.
const live = [];

function chrome(modal = "") {
  document.body.innerHTML = `<div id="pb-root" data-selection="h1">${modal}</div>`;

  const ctx = {
    el: document.getElementById("pb-root"),
    pushed: [],
    pushEvent(name, payload) {
      this.pushed.push([name, payload]);
    },
    handleEvent: () => {},
  };

  hooks.PbShortcuts.mounted.call(ctx);
  live.push(ctx);
  return ctx;
}

function key(init, target = document.body) {
  const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, ...init });
  target.dispatchEvent(event);
  return event;
}

const escape = (target) => key({ key: "Escape", code: "Escape" }, target);

const SOURCE_MODAL =
  '<div id="pb-source-modal" phx-window-keydown="close_source" phx-key="escape" data-pb-modal>' +
  '<section><button id="pb-source-close" type="button">x</button></section></div>';

beforeEach(() => {
  document.body.innerHTML = "";
});

afterEach(() => {
  while (live.length) hooks.PbShortcuts.destroyed.call(live.pop());
});

describe("escape while a modal is open", () => {
  it("is left to the modal: the hook pushes nothing and leaves the key alone", () => {
    const ctx = chrome(SOURCE_MODAL);

    const event = escape(document.getElementById("pb-source-close"));

    expect(ctx.pushed).toEqual([]);
    expect(event.defaultPrevented).toBe(false);
  });

  it("whatever has the focus outside the modal", () => {
    const ctx = chrome(SOURCE_MODAL);

    escape(document.body);
    escape(document.getElementById("pb-root"));

    expect(ctx.pushed).toEqual([]);
  });

  // ⌘S in the Code window still saves, and ⌘Z still undoes: only escape has an owner of its own.
  it("and every other shortcut still reaches the editor", () => {
    const ctx = chrome(SOURCE_MODAL);

    key({ metaKey: true, key: "s", code: "KeyS" });

    expect(ctx.pushed).toEqual([["shortcut", { key: "save", node_id: "h1" }]]);
  });

  it("goes back to the editor once the modal has gone", () => {
    const ctx = chrome(SOURCE_MODAL);

    document.getElementById("pb-source-modal").remove();
    const event = escape();

    expect(ctx.pushed).toEqual([["shortcut", { key: "escape", node_id: "h1" }]]);
    expect(event.defaultPrevented).toBe(true);
  });
});

describe("escape with no modal of that kind open", () => {
  it("is the editor's: it clears the selection and closes the sheet", () => {
    const ctx = chrome();

    escape();

    expect(ctx.pushed).toEqual([["shortcut", { key: "escape", node_id: "h1" }]]);
  });

  // The command palette and the media preview bind no escape of their own, and Settings drops its
  // binding while a sheet is over it: the editor's `shortcut("escape", …)` is what closes each, so
  // none carries the mark and the hook must still push.
  it("still reaches the editor for an overlay that does not close itself", () => {
    const ctx = chrome(
      '<div id="pb-command"><div></div></div>' +
        '<div id="pb-settings-modal" class="hidden" phx-key="escape"><section></section></div>',
    );

    escape();

    expect(ctx.pushed).toEqual([["shortcut", { key: "escape", node_id: "h1" }]]);
  });
});
