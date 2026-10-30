// SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
//
// SPDX-License-Identifier: Apache-2.0

import { afterEach, describe, expect, test } from "vitest";

import BuilderHooks from "../js/index.js";

afterEach(() => {
  document.body.innerHTML = "";
});

// A chip puts its variable where the caret last was, in whichever text field of the SEO tab that
// was, and tells the form it changed.
describe("PbSeoFields", () => {
  function form() {
    document.body.innerHTML = `
      <form id="pb-seo-form">
        <input type="text" name="seo[title]" value="About us" data-seo-vars />
        <textarea name="seo[description]" data-seo-vars>Hello</textarea>
        <input type="text" name="seo[plain]" value="Plain" />
        <input type="text" id="pb-seo-image" name="seo[image]" value="" data-seo-vars />
        <select name="seo[type]"><option value="">Default</option></select>
        <button type="button" data-seo-var="{{site.name}}">site.name</button>
      </form>`;

    const el = document.querySelector("form");
    const hook = Object.create(BuilderHooks.PbSeoFields);
    const handlers = {};

    hook.el = el;
    hook.handleEvent = (name, handler) => (handlers[name] = handler);
    hook.mounted();

    return { el, hook, handlers, chip: el.querySelector("[data-seo-var]") };
  }

  test("types a value the editor sends into its field, and announces it", () => {
    const { el, handlers } = form();
    const seen = [];

    el.addEventListener("input", (event) => seen.push([event.target.name, event.target.value]));
    handlers["pb-seo-set"]({ id: "pb-seo-image", value: "/uploads/cover.png" });

    expect(el.querySelector("#pb-seo-image").value).toBe("/uploads/cover.png");
    expect(seen).toEqual([["seo[image]", "/uploads/cover.png"]]);

    handlers["pb-seo-set"]({ id: "pb-seo-missing", value: "/x.png" });
    expect(seen.length).toBe(1);
  });

  function focus(field, caret) {
    field.focus();
    field.setSelectionRange(caret, caret);
  }

  test("inserts at the caret of the field last focused", () => {
    const { el, chip } = form();
    const title = el.querySelector("[name='seo[title]']");

    focus(title, 5);
    chip.focus();
    chip.click();

    expect(title.value).toBe("About{{site.name}} us");
    expect(title.selectionStart).toBe(5 + "{{site.name}}".length);
    expect(document.activeElement).toBe(title);
  });

  test("replaces a selection", () => {
    const { el, chip } = form();
    const description = el.querySelector("[name='seo[description]']");

    description.focus();
    description.setSelectionRange(0, 5);
    chip.click();

    expect(description.value).toBe("{{site.name}}");
  });

  test("announces the change so the form sends it", () => {
    const { el, chip } = form();
    const title = el.querySelector("[name='seo[title]']");
    const seen = [];

    el.addEventListener("input", (event) => seen.push(event.target.name));
    focus(title, 0);
    chip.click();

    expect(seen).toEqual(["seo[title]"]);
  });

  test("leaves a field that takes no variables alone, and fills the title's end instead", () => {
    const { el, chip } = form();
    const title = el.querySelector("[name='seo[title]']");
    const plain = el.querySelector("[name='seo[plain]']");

    focus(title, 0);
    focus(plain, 5);
    chip.click();

    expect(plain.value).toBe("Plain");
    expect(title.value).toBe("About us{{site.name}}");
  });

  test("goes to the end of the title before any field has been focused, and stays there", () => {
    const { el, chip } = form();
    const title = el.querySelector("[name='seo[title]']");

    el.querySelector("select").focus();
    chip.click();

    expect(title.value).toBe("About us{{site.name}}");
    expect(document.activeElement).toBe(title);
    expect(el.querySelector("[name='seo[description]']").value).toBe("Hello");

    chip.click();
    expect(title.value).toBe("About us{{site.name}}{{site.name}}");
  });

  test("finds the field again after it was replaced", () => {
    const { el, chip } = form();
    const title = el.querySelector("[name='seo[title]']");

    focus(title, 0);

    const replaced = title.cloneNode();
    replaced.value = "New";
    title.replaceWith(replaced);
    replaced.setSelectionRange(3, 3);
    chip.click();

    expect(replaced.value).toBe("New{{site.name}}");
  });

  test("stops listening when destroyed", () => {
    const { el, hook, chip } = form();
    const title = el.querySelector("[name='seo[title]']");

    focus(title, 0);
    hook.destroyed();
    chip.click();

    expect(title.value).toBe("About us");
  });
});
