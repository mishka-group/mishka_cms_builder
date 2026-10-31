# Changelog for MishkaCmsBuilder 0.0.1

- Initial version: [mishka.tools/cms](https://mishka.tools/cms)
- The visual editor is its own package, split out of mishka_cms_core 0.0.3. It needs mishka_cms_core 0.0.4, mishka_gervaz 0.0.3 and mishka_installer 0.1.15 or later
- Two tests that raced the editor's async work now wait for it, so the suite no longer fails when the LiveView is slower than the test
- The release runs on Erlang 29.1.2 and Elixir 1.20.5, with the temporary OTP 29.0.5 pin removed
- `igniter_js` is 0.5.2 and every dependency is at its latest release, including `phoenix_html` 4.4.0, which fixes a security advisory
- Escape closes the Code window, Find, Settings, Examples, the reload and leave questions and the new-folder form without leaving their backdrop over the editor; the editor's keyboard hook leaves Escape to an open modal
- The Preview bar says Preview ▸ Open in a new tab comes once a draft is saved, instead of pointing to that entry before it exists
- The Desktop canvas lays the page out at least 1180px wide and scales it to fit, so it no longer shows the site's tablet layout; Tablet and Mobile scale down instead of running off a narrow canvas
- A `<.form>` and every other function component keep their class on the canvas, with the Inspector's styles merged in as on the published page; their `phx-*` bindings are still left out. A child of a parent whose class has `space-y-*`, `space-x-*` or `divide-*` is drawn as that parent's own child, not inside the editor's box, so a form's gaps match the preview: an `<.input>`'s own `mb-2` outranks the form's `space-y-4` on the canvas as on the page
- A required property left empty, or text where a component takes a list or a map, is named as what stops a publish: the Inspector says the page cannot be published without it, and the refusal reads "Not published —", since drafts, autosave and Code Apply still save it
- A drawer or `chelekom-sidebar` opened in place on the canvas takes its content's height instead of keeping `h-screen` and standing as tall as the viewport over the page, and stays in view instead of keeping the `-translate-x-full` (Tailwind v4's `translate` property) that slid a drawer, or a sidebar on a narrow device, off the canvas; a modal is drawn as before
- Custom CSS applied in Draft says the canvas shows it now and the new-tab draft preview only after publishing, since that preview is compiled from the saved stylesheets and the held rule is written only by the publish
- Selecting a slot in the layers rail, such as a sidebar's `<:item>`, rings the component it belongs to on the canvas, so an overlay opened in place stays open instead of snapping back to `fixed` and the full height of the screen
