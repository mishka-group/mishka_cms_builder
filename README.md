<div align="center">

[![Buy Me a Coffee](https://img.shields.io/badge/Buy_Me_a_Coffee-mishkagroup-ffdd00?style=flat-square&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/mishkagroup)
[![GitHub Sponsors](https://img.shields.io/badge/GitHub_Sponsors-mishka--group-ea4aaa?style=flat-square&logo=github)](https://github.com/sponsors/mishka-group)

# Mishka CMS Builder

**The visual [page builder for Mishka CMS](https://mishka.tools/cms): a drag-and-drop editor for pages, layouts and components, built on Phoenix LiveView.**

[Website](https://mishka.tools/cms) · [Documentation](https://mishka.tools/cms/docs) · [Hire us](https://mishka.tools/hire-us)

</div>

## 📖 What is Mishka CMS Builder?

`mishka_cms_builder` is the visual editor of Mishka CMS. It adds the editor itself (a canvas, a palette of blocks and components, a Layers tree and the Studio panels), the admin pages that open it, and the records it keeps: the history of each edit, review notes and saved snippets.

It is optional. [mishka_cms_core](https://github.com/mishka-group/mishka_cms_core) owns the model of a page and the rules every page must satisfy (the `MishkaCmsCore.Runtime.Authoring` modules), so pages, layouts, components and error pages are written, validated and compiled the same way with or without this package. A CMS that does not install it simply has no editor: the dashboards show no "open in the editor" button, and a page is written in its form or its code tab.

## 🧩 Part of Mishka CMS

Mishka CMS Builder is an extension of [Mishka CMS](https://mishka.tools/cms), an open source real-time CMS. It runs on [mishka_cms_core](https://github.com/mishka-group/mishka_cms_core), the engine, inside the [mishka_cms](https://github.com/mishka-group/mishka_cms) application, and it plugs into the core through events, behaviours and configuration, so the core never names a module of this package.

## ✨ Features

- Drag and drop: place a block or a component from the palette on the canvas, move it in the Layers tree, edit text in place, with drop hints while you drag. The canvas is the real page in an iframe.
- The same editor for pages, layouts, components and error pages, with example and wizard previews for components.
- Studio, the design side of the editor: design tokens with an export (Tailwind, CSS variables, JSON or Elixir), component presets and the UI kit registry. Its switches, such as locking the tokens, are settings under `cms_builder.studio.`.
- Undo and redo with the keyboard or the menu, and a history timeline of every edit with restore points. The history of a deleted draft is released with it.
- Review notes pinned to a node, with `@mentions` that notify the person named (each person can turn that off in their notification preferences), resolve and reopen, and live avatars of everyone in the same session.
- Snippets: save a selection and insert it again from Studio. An extension can ship a snippet that is installed with it.
- Drafts: save the page as a draft, open it later, fork it or delete it.
- Card previews: hover a palette card to see it rendered, redrawn when the site's components are recompiled.
- Everything an editor needs around the canvas: the SEO settings modal, the assets sheet, the code tab, zoom, resizable panels, a light and dark theme, a context menu and a guard against leaving with unsaved changes.
- The editor's history appears in the CMS's activity log beside the other changes to a site.

## 🚀 Getting started

Mishka CMS Builder is installed with [Mishka CMS](https://github.com/mishka-group/mishka_cms#-getting-started). Add it from Hex:

```elixir
{:mishka_cms_builder, "~> 0.0.1"}
```

[Mishka CMS](https://github.com/mishka-group/mishka_cms) loads it from `__extensions/mishka_cms_builder` instead when that folder exists.

A host registers it in two places and adds nothing else:

1. `MishkaCmsBuilder` in `ash_domains`, and `MishkaCmsBuilderWeb` in the core's `extensions` list, both in `config/config.exs`. The editor's routes and admin pages come from `MishkaCmsBuilderWeb`; its tables (`page_builder_events`, `page_builder_snapshots`, `page_comments` and `builder_snippets`) come from the domain, so the host's `mix ash.codegen` includes them. The package's own application starts by itself, after `:mishka_cms_core` (which starts `MishkaCmsCore.PubSub` for it), so the host adds no child to its supervision tree for the editor.
2. The editor's hooks ship as an ES module in `assets/js`, reached through `package.json`. Import them in the admin's `app.js` beside the core's:

   ```js
   import CoreHooks from "mishka_cms_core";
   import BuilderHooks from "mishka_cms_builder";

   boot({ ...SharedHooks, ...CoreHooks, ...BuilderHooks });
   ```

   They import nothing from npm, so the host's bundler only has to find the package: put the directory that holds the Mishka packages (`deps`, or `__extensions` when you work from checkouts) on esbuild's `NODE_PATH`. The core's `mix admin_css` scans an extension's `assets/js` for the classes the hooks write, so the admin stylesheet needs no change.

The editor opens from the Pages, Layouts, Components and Error pages dashboards, under `/admin/dashboard/runtime/builder/:section`. It adds no permission of its own: it uses `admin:dashboard:runtime:page`, `admin:dashboard:runtime:layout`, `admin:dashboard:runtime:component`, `admin:dashboard:runtime:error_page` and `admin:dashboard:code`.

### Configuration

All of it is optional:

| Key | Default | What it does |
| --- | --- | --- |
| `config :mishka_cms_builder, coalesce_ms:` | `600` | Edits of one node's text inside this many milliseconds are one undo step. |
| `config :mishka_cms_builder, history_bytes:` | 8 MB | The memory one session's history may hold. |
| `config :mishka_cms_builder, marketplace:` | `MishkaCmsBuilder.Marketplace.Kits` | The adapter behind Studio's design tokens and kit registry. |
| `config :mishka_cms_builder, ai_backend:` | `MishkaCmsBuilder.AiBackend.Echo` | The backend behind the Assistant rail. The default only echoes. |
| `config :mishka_cms_builder, demo_data: true` | off | Shows sample history and Assistant transcripts while those rails are empty. Development only. |

Its settings live under the `cms_builder.` prefix (for example `cms_builder.studio.lock_tokens`), and the editor's permissions are enough to write them: a page editor needs no `admin:dashboard:setting` for these keys.

## 🔌 Events

The editor's plugin contract (`builder:*` events such as `builder:node:before_insert`, and `page:form:submitted`) is catalogued in the core's `MishkaCmsCore.Builder.Events`, so an extension can add to the editor without depending on this package. This package fires `cms_builder:page_comment:after_create` and the other `after_*` events of its review notes and snippets, and listens on `runtime:document:editor_url`, `runtime:provision:snippets`, `activity:sources`, `settings:register`, `sidebar:menus`, `runtime:after_module_compile` and the destroy events of drafts.

## 📚 Documentation

- [Mishka CMS documentation](https://mishka.tools/cms/docs)
- [Mishka Installer documentation](https://mishka.tools/installer/docs), for plugins and events
- The [Mishka blog](https://mishka.tools/blog)

## 💬 Community and support

- Report a bug or ask a question in [GitHub issues](https://github.com/mishka-group/mishka_cms_builder/issues).
- Read about new releases on the [Mishka blog](https://mishka.tools/blog).
- For a custom editor feature or priority support, [hire the Mishka team](https://mishka.tools/hire-us).

## 💖 Support the project

Mishka CMS and its extensions are free and open source. You can support their development through [GitHub Sponsors](https://github.com/sponsors/mishka-group) or [Buy Me a Coffee](https://www.buymeacoffee.com/mishkagroup).

## 📜 License

Apache License 2.0. See [LICENSE](LICENSE).
