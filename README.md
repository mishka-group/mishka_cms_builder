<div align="center">

[![Buy Me a Coffee](https://img.shields.io/badge/Buy_Me_a_Coffee-mishkagroup-ffdd00?style=flat-square&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/mishkagroup)
[![GitHub Sponsors](https://img.shields.io/badge/GitHub_Sponsors-mishka--group-ea4aaa?style=flat-square&logo=github)](https://github.com/sponsors/mishka-group)

# Mishka CMS Builder

**The visual [page builder for Mishka CMS](https://mishka.tools/cms): a drag-and-drop editor for pages, layouts and components, built on Phoenix LiveView.**

[Website](https://mishka.tools/cms) · [Documentation](https://mishka.tools/cms/docs) · [Hire us](https://mishka.tools/hire-us)

</div>

## 📖 What is Mishka CMS Builder?

`mishka_cms_builder` is an Elixir library built on Ash and Phoenix LiveView. It is the visual editor of Mishka CMS. It holds the editor itself (a canvas, a palette of blocks and components, a Layers tree and the Studio panels), the admin pages that open it, and the records it keeps: the history of each edit, review notes and saved snippets.

It was split out of [mishka_cms_core](https://github.com/mishka-group/mishka_cms_core), and it is optional. The core owns the model of a page and the rules every page must satisfy, in `MishkaCmsCore.Runtime.Authoring`. Pages, layouts, components and error pages are written, validated and compiled the same way with or without this package. A CMS that does not install it has no editor: the dashboards show no "open in the editor" button, and a page is written in its form or its code tab.

The package needs Elixir 1.20 or newer, `mishka_cms_core` 0.0.3 or newer (the first core release with the events this package answers), Phoenix LiveView 1.2 and Ash 3.37 with AshPostgres. Mix fetches them with it.

## 🧩 Part of Mishka CMS

Mishka CMS Builder is an extension of [Mishka CMS](https://mishka.tools/cms), an open source real-time CMS. It runs on [mishka_cms_core](https://github.com/mishka-group/mishka_cms_core), the engine, inside the [mishka_cms](https://github.com/mishka-group/mishka_cms) application. It plugs into the core through events, behaviours and configuration, so the core never names a module of this package.

## ✨ Features

- Drag and drop. Place a block or a component from the palette on the canvas, move it in the Layers tree and edit text in place. Drop hints show where it will land. The canvas is a LiveView of its own, shown in an iframe.
- One editor for pages, layouts, components and error pages, with example and wizard previews for components.
- Studio, the design side of the editor: design tokens that export as Tailwind, CSS variables, JSON or Elixir, component presets and the UI kit registry. Its switches, such as locking the tokens, are settings under `cms_builder.studio.`.
- Undo and redo from the keyboard or the menu, and a history timeline of every edit with restore points. When a draft is deleted, its history moves to the timeline of the live record.
- Review notes pinned to a node, with `@mentions` that notify the person named (each person can turn that off in their notification preferences), resolve and reopen, and live avatars of everyone in the same session.
- Snippets. Save a selection and insert it again from Studio. An extension can ship a snippet that is installed with it.
- Drafts. Save the page as a draft, open it later, fork it or delete it.
- Card previews. Hover a palette card to see it rendered. The previews are redrawn when the site's components are recompiled.
- Everything an editor needs around the canvas: the SEO settings modal, the assets sheet, the code tab, zoom, resizable panels, a light and dark theme, a context menu and a guard against leaving with unsaved changes.
- The editor's history appears in the activity log of the CMS, beside the other changes to a site.

## 🔐 Permissions

The editor adds no permission of its own. To open it, a person needs the runtime permission of the kind they edit (`admin:dashboard:runtime:page`, `admin:dashboard:runtime:layout`, `admin:dashboard:runtime:component` or `admin:dashboard:runtime:error_page`), or `admin:dashboard:code`, which opens every kind. Any one of these also lets them write the editor's own settings, so a page editor needs no `admin:dashboard:setting`.

The editor opens from the Pages, Layouts, Components and Error pages dashboards, under `/admin/dashboard/runtime/builder/:section`, and it keeps its canvas under `/admin/dashboard/runtime/builder-canvas/:token`.

## 🔌 How it plugs into the core

The core names no module of this package. Every link between them is an event, a behaviour or a config key, and an event nobody answers leaves the core as it was. The package answers these events:

| Event | Answered by | What it does |
| --- | --- | --- |
| `runtime:document:editor_url` | `MishkaCmsBuilder.Plugins.EditorUrl` | Gives the core the address of the editor for a page, layout, component or error page. With no answer the dashboards draw no editor button. |
| `runtime:provision:snippets` | `MishkaCmsBuilder.Plugins.ProvisionSnippet` | Saves the snippet an extension ships when it is set up on a site. A snippet the site already has is left alone. |
| `activity:sources` | `MishkaCmsBuilder.Activity.EditorHistory` | Adds the editor's history to the activity log, tagged `EDITOR`. |
| `settings:register` | `MishkaCmsBuilder.Plugins.Settings` | Registers the `cms_builder.` settings prefix and the two switches of the mention notification. |
| `sidebar:menus` | `MishkaCmsBuilderWeb.SidebarMenu` | Declares the editor and its canvas as admin pages. Neither is a link in the sidebar. |
| `runtime:after_module_compile` | `MishkaCmsBuilder.Plugins.CardPreviewInvalidator` | Drops the cached card previews, because a recompiled component can draw differently. |
| `cms_core:page_draft:after_destroy` and `after_master_destroy`, and the same two for `layout_draft` and `error_page_draft` | `MishkaCmsBuilder.Plugins.ReleaseDraftHistory` | Detaches the history of the deleted draft from it. |

These settings belong to the package:

| Key | What it holds |
| --- | --- |
| `cms_builder.studio.*` | The Studio switches: `registry_source`, `sync_tokens`, `lock_tokens`, `license_token`, `dark_pair` and `applied_preset`. |
| `cms_builder.preset.<component>` | The presets of one component, for one site. |
| `notify.cms_builder.page_comment.mentioned` | The site's switch for the notification sent to a person named in a review note. |
| `notify.pref.cms_builder.page_comment.mentioned` | The same switch for one person, under their notification preferences. |

The `settings:register` plugin registers one prefix definition for `cms_builder.`, so the permissions above write every key under it. Without this package such a key needs `admin:dashboard:setting`.

The package fires these events:

- `cms_builder:page_comment:after_<action>` and `cms_builder:snippet:after_<action>`, such as `cms_builder:page_comment:after_create`, from the `PluginHook` notifier of the review note and snippet resources. A create or update also fires `after_save`.
- The `builder:*` events and `page:form:submitted`, such as `builder:node:before_<op>` and `builder:node:after_<op>`. They are catalogued in the core's `MishkaCmsCore.Builder.Events`, which stays in the core so an extension can ship a plugin for the editor without depending on this package.

## 🚀 Getting started

Mishka CMS Builder is installed with [Mishka CMS](https://github.com/mishka-group/mishka_cms#-getting-started). To add it to a host yourself, take these steps.

Add it from Hex:

```elixir
{:mishka_cms_builder, "~> 0.0.1-alpha.1"}
```

[Mishka CMS](https://github.com/mishka-group/mishka_cms) loads it from `__extensions/mishka_cms_builder` instead when that folder exists.

Register the web module with the core and the domain with Ash, and turn the editor's strict checks on outside production:

```elixir
config :mishka_cms_core,
  extensions: [MishkaCmsCoreWeb, MishkaBlogWeb, MishkaDocumentWeb, MishkaCmsBuilderWeb]

config :mishka_cms,
  ash_domains: [
    MishkaCmsBuilder,
    MishkaDocument,
    MishkaBlog,
    MishkaCmsCore.Runtime,
    MishkaCmsCore.Accounts,
    MishkaCmsCore.Notify,
    MishkaCmsCore.Mail
  ]

config :mishka_cms_core, builder_strict: config_env() != :prod
```

The `builder_strict` line is needed because of how Mix compiles dependencies. `MishkaCmsCore.Runtime.Authoring.Strict` raises in development and test when something happens that the editor treats as impossible, and compiles to nothing in production. The core decides this when it compiles, and Mix compiles a dependency in `:prod`. Without the line, the checks are off in your development and test runs, and a bug stays silent. The core reads the key when it compiles, so after you change it run `mix deps.compile mishka_cms_core --force`.

The editor's four tables (`page_builder_events`, `page_builder_snapshots`, `page_comments` and `builder_snippets`) come from the `MishkaCmsBuilder` domain, so the host's own migrations create them:

```bash
mix ash.codegen add_cms_builder
mix ash.migrate
```

The host adds nothing else on the Elixir side:

- **Supervision tree.** The application of this package starts after `:mishka_cms_core`, which starts `MishkaCmsCore.PubSub` for it. It supervises the open sessions, their history, the card previews, the presence of the people in a session and its own plugins. None of them needs the repo at start, so the host adds no child.
- **Router and endpoint.** The editor's routes come from `MishkaCmsBuilderWeb.Routes` through `extension_routes(:admin_standalone)`, which the Mishka CMS router already calls inside its admin session. A host with its own router calls that macro in an admin `live_session` too.

### The JavaScript

The editor's hooks ship as ES module sources in `assets/js`, reached through the `main` of the root `package.json`, as the core's hooks are. Nothing is built ahead of time, and the hooks import nothing from npm, so the host's bundler only has to find the package by name. Import them in the admin's `app.js` beside the core's:

```js
import { boot } from "./boot";
import SharedHooks from "./shared_hooks";
import CoreHooks from "mishka_cms_core";
import BuilderHooks from "mishka_cms_builder";

boot({ ...SharedHooks, ...CoreHooks, ...BuilderHooks });
```

Spread both sets. The editor's templates also mount `PbCodeEditor` and `MediaThumb`, and those come from the core's hooks.

esbuild finds the package through `NODE_PATH`, as Phoenix does for its own deps. From Hex, the host's `deps` directory on the path is enough. Mishka CMS also looks in `__extensions` first, so a checkout wins over a stale copy in `deps`, and it puts `assets/node_modules` last, so the `sortablejs` import in the core's hooks resolves from the host's own npm tree:

```elixir
mishka_js =
  if System.get_env("MISHKA_DEPS") == "hex",
    do: [],
    else: [Path.expand("../__extensions", __DIR__)]

config :esbuild,
  version: "0.28.2",
  mishka_cms: [
    # args and cd: as in any Phoenix app
    env: %{
      "NODE_PATH" =>
        mishka_js ++
          [
            Path.expand("../deps", __DIR__),
            Mix.Project.build_path(),
            Path.expand("../assets/node_modules", __DIR__)
          ]
    }
  ]
```

The core's `mix admin_css` reads the `assets/js` folder of every package under `__extensions` and every `deps/mishka_*` package. The classes the hooks write reach the admin stylesheet, and the host changes nothing for them.

### Configuration

All of it is optional:

| Key | Default | What it does |
| --- | --- | --- |
| `config :mishka_cms_builder, coalesce_ms:` | `600` | Edits of one node's text inside this many milliseconds are one undo step. The package reads it when it compiles, so after a change run `mix deps.compile mishka_cms_builder --force`. |
| `config :mishka_cms_builder, history_bytes:` | 8 MB | The memory the history of one session may hold. |
| `config :mishka_cms_builder, marketplace:` | `MishkaCmsBuilder.Marketplace.Kits` | The adapter behind Studio's design tokens and kit registry. A module that implements the `MishkaCmsBuilder.Marketplace` behaviour. |
| `config :mishka_cms_builder, ai_backend:` | `MishkaCmsBuilder.AiBackend.Echo` | The backend behind the Assistant rail. The default only restates the request and says that no model is configured. |
| `config :mishka_cms_builder, demo_data: true` | off | Shows sample history and Assistant transcripts while those rails are empty. For development only. |

## 🛠️ Development

The package builds against `mishka_cms_core`, so check the two out side by side. `mix.exs` takes `mishka_cms_core`, `mishka_installer` and `mishka_gervaz` from `../<name>` when that folder is a git clone, and from Hex otherwise. Clone only the ones you change:

```bash
mkdir mishka && cd mishka
git clone https://github.com/mishka-group/mishka_cms_core.git
git clone https://github.com/mishka-group/mishka_cms_builder.git
cd mishka_cms_builder
mix deps.get
```

Use a real clone for core, not a `git worktree`. A worktree has a `.git` file instead of a `.git` folder, so `mix.exs` ignores it and takes the Hex release of core. The first compile builds core and everything under it, so it takes a while. `mix hex.build` and `mix hex.publish` skip the sibling folders on purpose, so a release always builds against Hex.

To work on the editor inside a running CMS, clone it into the `__extensions` folder of a [mishka_cms](https://github.com/mishka-group/mishka_cms) clone, as the core's README shows for the other packages:

```bash
git clone https://github.com/mishka-group/mishka_cms_builder.git __extensions/mishka_cms_builder
```

### Tests

The tests need PostgreSQL. `config/test.exs` reads `POSTGRES_HOST` (default `localhost`), `POSTGRES_USER` and `POSTGRES_PASSWORD` (both default `postgres`), and names the database `mishka_cms_builder_test` followed by `MIX_TEST_PARTITION`. The migrations are generated and not kept in git, so generate them first. `mix test` then runs `ash.setup --quiet` and the suite:

```bash
MIX_ENV=test mix ash.codegen ci
MIX_ENV=test mix localize.download_locales fa
POSTGRES_HOST=localhost mix test
```

Run `mix test` without an exported `MIX_ENV`. `mishka_installer` reads `MIX_ENV` when it compiles, and an exported value overrides the `project_env` in `config/test.exs`.

Most of the suite shares the runtime's global state and runs one module at a time (`async: false`), so CI deals the test files out over four partitions, each with its own database. Run the command once for each value of `MIX_TEST_PARTITION` from 1 to 4:

```bash
MIX_TEST_PARTITION=1 mix test --warnings-as-errors --partitions 4
```

The tests run on the harness the core ships in its own `lib`, under `MishkaCmsCore.Test`. `test/test_helper.exs` calls `MishkaCmsCore.Test.Boot.start!/1`, which starts the repo, Oban, the caches, the runtime compiler, the sign-in supervisor and the endpoint, and waits for the plugins of this package. The test cases use `MishkaCmsCore.DataCase` and `MishkaCmsCore.ConnCase`, and the helpers of `MishkaCmsCore.Test.Admin` (signed-in connections), `MishkaCmsCore.Test.Factory` (records) and `MishkaCmsCore.Test.Installer` (test plugins). `MishkaCmsBuilder.LiveCase` in `test/support` adds the helpers that drive the editor.

The hooks have their own tests, run with Vitest in jsdom:

```bash
cd assets
bun install
bun run test
```

### The full check

`mix ci` runs the same steps as the CI jobs, in the test environment: `hex.audit`, `compile --warnings-as-errors`, `format --check-formatted`, `credo --strict`, `sobelow --config`, `deps.audit`, `dialyzer`, `ex_dna --max-clones 4` and `test`.

## 📚 Documentation

- [Mishka CMS documentation](https://mishka.tools/cms/docs), which is still being written
- [Mishka Installer documentation](https://mishka.tools/installer/docs), for plugins and events
- [Mishka Gervaz documentation](https://mishka.tools/gervaz/docs), for the Ash admin DSL behind the editor's tables and forms
- The [Mishka blog](https://mishka.tools/blog)

## 💬 Community and support

- Report a bug or ask a question in [GitHub issues](https://github.com/mishka-group/mishka_cms_builder/issues).
- Report a security bug by email to `info@mishka.tools`, as the [security policy](https://github.com/mishka-group/mishka_cms_builder/security/policy) says.
- Read about new releases on the [Mishka blog](https://mishka.tools/blog).
- For a custom editor feature or priority support, [hire the Mishka team](https://mishka.tools/hire-us).

## 💖 Support the project

Mishka CMS and its extensions are free and open source. You can support their development through [GitHub Sponsors](https://github.com/sponsors/mishka-group) or [Buy Me a Coffee](https://www.buymeacoffee.com/mishkagroup).

## 📜 License

Apache License 2.0. See [LICENSE](LICENSE). Every tracked file carries an SPDX header or is covered by `REUSE.toml`, and the REUSE workflow checks it.
