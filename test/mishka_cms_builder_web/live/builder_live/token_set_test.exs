# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.BuilderLive.TokenSetTest do
  @moduledoc """
  A design token set in the Studio: the `set_token` event, asked through `builder:token:before_set`
  before anything is written.

  The value a plugin returns is the value written, a plugin's refusal is shown to the author and
  writes nothing, and with no plugin the value is written as typed.
  """
  use MishkaCmsBuilder.LiveCase

  alias MishkaCmsBuilder.Tokens
  alias MishkaCmsBuilder.Test.Plugins.BuilderTokenGate

  @key "iris"

  defp value_of(site_id, key) do
    site_id
    |> Tokens.list()
    |> Enum.find(&(&1.key == key))
    |> case do
      nil -> nil
      token -> token.value
    end
  end

  setup %{conn: conn, page: page} do
    Application.put_env(
      :mishka_cms_builder,
      :marketplace,
      MishkaCmsBuilder.Marketplace.Mock
    )

    on_exit(fn -> Application.delete_env(:mishka_cms_builder, :marketplace) end)

    {:ok, _theme} =
      MishkaCmsCore.Runtime.Stylesheet
      |> Ash.Changeset.for_create(
        :master_create,
        %{
          name: "token-set-theme-#{System.unique_integer([:positive])}",
          kind: :theme,
          content: ":root {\n  --#{@key}: #5b57d6;\n}\n",
          site_id: nil,
          active: true
        },
        authorize?: false
      )
      |> Ash.create()

    %{view: open_studio(conn, page)}
  end

  test "writes the value the author typed", %{view: view, site: site} do
    render_click(view, "set_token", %{"key" => @key, "value" => "#123456"})

    assert value_of(site.id, @key) == "#123456"
    refute has_element?(view, "#flash-error")
  end

  # ONE BUILD PER EDIT, AND IT IS THE ROW'S. Saving the sheet queues the site's CSS rebuild, which
  # builds and stores the CSS (`MishkaCmsBuilder.TokensTest`). The event used to run
  # a second Tailwind build of its own, keep nothing of it, and make the author wait for it.
  test "runs no Tailwind build while the author waits", %{view: view, site: site} do
    test_pid = self()
    handler = "token-set-build-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:mishka_cms, :runtime, :compilers, :tailwind, :start],
        fn _event, _measurements, meta, _config -> send(test_pid, {:tailwind, meta[:site]}) end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    render_click(view, "set_token", %{"key" => @key, "value" => "#123456"})

    assert value_of(site.id, @key) == "#123456"
    refute_received {:tailwind, _site}, "the Studio built the site's CSS and threw it away"
  end

  # THE EXPORT IS A FILE PEOPLE PASTE. The table read the edited token again, but the Generated
  # output, the Copy button that carries it and the toolbar badge kept the list the Studio read when
  # it opened: the row said CUSTOM while the export still held the old colour and Copy copied it,
  # until the Studio was closed and opened again.
  test "the Generated output and its Copy follow the edit while the Studio stays open", %{
    view: view,
    site: site
  } do
    assert export(view) =~ "#5b57d6"
    assert copied(view) =~ "#5b57d6"
    refute has_element?(view, "#pb-studio [data-role=pb-studiobadge]")

    render_click(view, "set_token", %{"key" => @key, "value" => "#b91c1c"})

    assert export(view) =~ "'#{@key}': '#b91c1c'"
    refute export(view) =~ "#5b57d6"
    assert copied(view) =~ "'#{@key}': '#b91c1c'"
    refute copied(view) =~ "#5b57d6"

    custom = site.id |> Tokens.list() |> Enum.count(& &1.custom?)
    assert custom > 0, "the edit is this site's own override"

    assert view |> element("#pb-studio [data-role=pb-studiobadge]") |> render() =~
             to_string(custom)
  end

  # The Inspector's site colours are the same list, read at mount, so a swatch went on painting the
  # colour the token no longer has.
  test "the Inspector's site colours follow the edit", %{view: view} do
    render_click(view, "set_token", %{"key" => @key, "value" => "#b91c1c"})
    _settled = render_async(view)

    assert {@key, "#b91c1c", _label} =
             Enum.find(live_assigns(view).style_tokens, &(elem(&1, 0) == @key))
  end

  # BACK AT THE KIT'S VALUE IS NOT CUSTOM. Setting a token and then setting it back left the row
  # labelled CUSTOM and the toolbar's badge at one, because the site's sheet still declared the
  # value it shadowed.
  test "a token set back to the kit's value is no longer custom", %{view: view} do
    render_click(view, "set_token", %{"key" => @key, "value" => "#b91c1c"})
    _settled = render_async(view)
    assert view |> element("#pb-token-#{@key}") |> render() =~ "Custom"
    assert has_element?(view, "#pb-studio [data-role=pb-studiobadge]")

    render_click(view, "set_token", %{"key" => @key, "value" => "#5b57d6"})
    _settled = render_async(view)

    refute view |> element("#pb-token-#{@key}") |> render() =~ "Custom"
    refute has_element?(view, "#pb-studio [data-role=pb-studiobadge]")
  end

  # AND THE WAY BACK IS ONE PRESS, on the row it is about, offered only where there is a value to go
  # back to. It writes through `set_token`, so a design-system plugin is asked about it like any
  # other value.
  test "a custom token's row resets it to the kit's value", %{view: view, site: site} do
    refute has_element?(view, "#pb-token-reset-#{@key}")

    render_click(view, "set_token", %{"key" => @key, "value" => "#b91c1c"})
    _settled = render_async(view)

    assert view |> element("#pb-token-reset-#{@key}") |> render() =~ "#5b57d6"

    view |> element("#pb-token-reset-#{@key}") |> render_click()
    _settled = render_async(view)

    assert value_of(site.id, @key) == "#5b57d6"
    refute has_element?(view, "#pb-token-reset-#{@key}")
    refute has_element?(view, "#pb-studio [data-role=pb-studiobadge]")
    refute has_element?(view, "#flash-error")
  end

  # Read as the browser reads them — the text of the block and the attribute the PbCopy hook copies —
  # so the quotes of the generated file compare as quotes, not as escaped HTML.
  defp export(view),
    do: view |> element("#pb-token-export-body pre") |> render() |> fragment() |> LazyHTML.text()

  defp copied(view) do
    [copy] =
      view
      |> element("#pb-token-copy")
      |> render()
      |> fragment()
      |> LazyHTML.attribute("data-copy")

    copy
  end

  defp fragment(html), do: LazyHTML.from_fragment(html)

  describe "with a design-system plugin" do
    setup do: register_plugin(BuilderTokenGate, "builder:token:before_set")

    test "writes the value the plugin snapped it to", %{view: view, site: site} do
      render_click(view, "set_token", %{"key" => @key, "value" => "snap-me"})

      assert value_of(site.id, @key) == BuilderTokenGate.snapped()
    end

    test "shows a refusal and writes nothing", %{view: view, site: site} do
      before = value_of(site.id, @key)

      html =
        render_click(view, "set_token", %{"key" => @key, "value" => BuilderTokenGate.refused()})

      assert html =~ "That value is not on the scale."
      assert value_of(site.id, @key) == before
    end
  end
end
