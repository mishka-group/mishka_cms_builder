// SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
//
// SPDX-License-Identifier: Apache-2.0

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import hooks from "../js/index.js";

// LEAVING PUBLISH MODE WITH CHANGES IS THE ONE WAY TO LOSE WORK IN THE EDITOR, so a click on a link
// out is handed to the server, which offers to keep the work before going. The editor is a
// live_session of its own, so its links to the rest of the admin are plain `href`s, page loads,
// and only its links to its own pages are live: the guard has to catch both, and nothing else.
const EDITOR = "/admin/dashboard/runtime/builder/page/p1";
const live = [];

function guard({ armed = true, links = "" } = {}) {
  document.body.innerHTML = `
    <span id="pb-leave-guard" data-armed="${armed}" class="hidden"></span>
    ${links}
  `;

  const ctx = { el: document.getElementById("pb-leave-guard"), pushEvent: vi.fn() };
  hooks.PbLeaveGuard.mounted.call(ctx);
  live.push(ctx);
  return ctx;
}

// Whether the click got past the guard to the page, which stands in for the browser following it:
// a click the guard takes never reaches the listener, and one it leaves is stopped there instead,
// because jsdom cannot follow a link.
let reached;

function click(selector, init = {}) {
  const event = new MouseEvent("click", { bubbles: true, cancelable: true, button: 0, ...init });
  document.querySelector(selector).dispatchEvent(event);
  return event;
}

describe("the leave guard", () => {
  const follow = (event) => {
    reached = true;
    event.preventDefault();
  };

  beforeEach(() => {
    reached = false;
    window.history.replaceState({}, "", EDITOR);
    document.addEventListener("click", follow);
  });

  afterEach(() => {
    while (live.length) hooks.PbLeaveGuard.destroyed.call(live.pop());
    document.removeEventListener("click", follow);
    document.body.innerHTML = "";
  });

  describe("with unpublished changes in publish mode", () => {
    it("hands a plain link to the rest of the admin to the server", () => {
      const ctx = guard({ links: '<a id="out" href="/admin/dashboard/runtime/pages">Back</a>' });

      const event = click("#out");

      expect(ctx.pushEvent).toHaveBeenCalledWith("leaving", {
        to: "/admin/dashboard/runtime/pages",
      });
      expect(event.defaultPrevented).toBe(true);
      expect(reached).toBe(false);
    });

    it("hands a live link to another of the editor's pages to the server", () => {
      const ctx = guard({
        links: `<a id="live" href="/admin/dashboard/runtime/builder/component/c1"
                   data-phx-link="redirect" data-phx-link-state="push">Edit</a>`,
      });

      click("#live");

      expect(ctx.pushEvent).toHaveBeenCalledWith("leaving", {
        to: "/admin/dashboard/runtime/builder/component/c1",
      });
      expect(reached).toBe(false);
    });

    it("sends the path with its query, even when the link spells out this origin", () => {
      const ctx = guard({
        links: `<a id="q" href="/admin/dashboard/runtime/pages?site_id=s1">Pages</a>
                <a id="abs" href="${window.location.origin}/admin/dashboard/settings">Settings</a>`,
      });

      click("#q");
      click("#abs");

      expect(ctx.pushEvent.mock.calls).toEqual([
        ["leaving", { to: "/admin/dashboard/runtime/pages?site_id=s1" }],
        ["leaving", { to: "/admin/dashboard/settings" }],
      ]);
    });

    it("catches a click on what is inside the link", () => {
      const ctx = guard({
        links: '<a href="/admin/dashboard/settings"><span id="label">Settings</span></a>',
      });

      click("#label");

      expect(ctx.pushEvent).toHaveBeenCalledWith("leaving", { to: "/admin/dashboard/settings" });
    });

    it("reads the flag at the click, so a change that arms it needs no remount", () => {
      const ctx = guard({
        armed: false,
        links: '<a id="out" href="/admin/dashboard/runtime/pages">Back</a>',
      });

      ctx.el.dataset.armed = "true";
      click("#out");

      expect(ctx.pushEvent).toHaveBeenCalledTimes(1);
    });

    it("objects when the tab is closed or reloaded", () => {
      guard();

      const event = new Event("beforeunload", { cancelable: true });
      window.dispatchEvent(event);

      expect(event.defaultPrevented).toBe(true);
    });

    // None of these unloads the editor, or the browser opens them somewhere else, or the server
    // would refuse them as a destination: each is left to the browser.
    for (const [what, link, init] of [
      ["a patch link, which stays in this editor", 'href="/x?tab=a" data-phx-link="patch"'],
      ["a jump to a fragment of this page", 'href="#layers"'],
      ["an empty fragment", 'href="#"'],
      ["a link opening a new tab", 'href="/admin/dashboard/settings" target="_blank"'],
      ["a download", 'href="/admin/dashboard/export.json" download'],
      ["another origin", 'href="https://mishka.tools/chelekom/docs"'],
      ["a mailto link", 'href="mailto:team@example.com"'],
      ["a click with a modifier key", 'href="/admin/dashboard/settings"', { metaKey: true }],
      ["a middle click", 'href="/admin/dashboard/settings"', { button: 1 }],
    ]) {
      it(`leaves ${what} alone`, () => {
        const ctx = guard({ links: `<a id="it" ${link}>it</a>` });

        click("#it", init);

        expect(ctx.pushEvent).not.toHaveBeenCalled();
        expect(reached).toBe(true);
      });
    }

    it("leaves a link alone that the page already handled", () => {
      const ctx = guard({ links: '<a id="it" href="/admin/dashboard/settings">it</a>' });
      const handled = (event) => event.preventDefault();
      window.addEventListener("click", handled, true);

      click("#it");
      window.removeEventListener("click", handled, true);

      expect(ctx.pushEvent).not.toHaveBeenCalled();
    });
  });

  describe("with nothing at stake", () => {
    it("lets every link go without asking the server", () => {
      const ctx = guard({
        armed: false,
        links: `<a id="out" href="/admin/dashboard/runtime/pages">Back</a>
                <a id="live" href="/admin/dashboard/runtime/builder/component/c1"
                   data-phx-link="redirect" data-phx-link-state="push">Edit</a>`,
      });

      click("#out");
      click("#live");

      expect(ctx.pushEvent).not.toHaveBeenCalled();
    });

    it("does not object to closing the tab", () => {
      guard({ armed: false });

      const event = new Event("beforeunload", { cancelable: true });
      window.dispatchEvent(event);

      expect(event.defaultPrevented).toBe(false);
    });
  });

  it("stops guarding once the hook is torn down", () => {
    const ctx = guard({ links: '<a id="out" href="/admin/dashboard/runtime/pages">Back</a>' });
    hooks.PbLeaveGuard.destroyed.call(live.pop());

    click("#out");
    const event = new Event("beforeunload", { cancelable: true });
    window.dispatchEvent(event);

    expect(ctx.pushEvent).not.toHaveBeenCalled();
    expect(event.defaultPrevented).toBe(false);
  });
});
