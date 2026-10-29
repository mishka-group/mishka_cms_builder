// SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
//
// SPDX-License-Identifier: Apache-2.0

// THE PACKAGE'S ENTRY, named by `main` and `module` in the root `package.json`. A host's admin
// bundle imports it by name and hands the hooks to its LiveSocket with its own:
//
//     import BuilderHooks from "mishka_cms_builder";
//     boot({ ...SharedHooks, ...CoreHooks, ...BuilderHooks });
//
// esbuild finds the package through the host's `NODE_PATH`: `deps/mishka_cms_builder` for the Hex
// release, `__extensions/mishka_cms_builder` for a checkout. These are ES module sources, bundled by
// the host; nothing here is built ahead of time.

import Hooks from "./hooks.js";

export default Hooks;
export { PB_KEYS, PB_SHORTCUTS } from "./hooks.js";
