# Changelog for MishkaCmsBuilder 0.0.1

- Initial version: [mishka.tools/cms](https://mishka.tools/cms)
- The visual editor is its own package, split out of mishka_cms_core 0.0.3. It needs mishka_cms_core 0.0.3 or later
- Two tests that raced the editor's async work now wait for it, so the suite no longer fails when the LiveView is slower than the test
- The release runs on Erlang 29.1.2 and Elixir 1.20.5, with the temporary OTP 29.0.5 pin removed
- `igniter_js` is 0.5.2 and every dependency is at its latest release, including `phoenix_html` 4.4.0, which fixes a security advisory
