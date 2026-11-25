# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.KitAttrsTest do
  @moduledoc """
  What a kit says about its own attributes reaches the editor: the sections and words it names, a
  choice list an extension reads for the site, an attribute that is for the canvas only, and the
  visitor the page hands a block itself.

  A save writes the page a published page draws: a block that declares `current_user` is handed the
  page's visitor, which the author never writes and the Inspector never offers, and the canvas-only
  attribute is left out (`MishkaCmsCore.Runtime.Authoring.Tree.saved/2`).

  It does NOT prove that a published page then draws the block for the signed-in visitor: the page
  reads the visitor because its source names it (`MishkaCmsCore.Runtime.Compilers.UserClosure`),
  which the core's tests prove, and the extension's own tests prove its block.
  """
  use MishkaCmsBuilder.LiveCase

  alias MishkaCmsBuilder.AttrChoices
  alias MishkaCmsBuilder.Test.Plugins.BuilderAttrChoicesPlugin, as: ChoicesPlugin
  alias MishkaCmsBuilderWeb.Live.Panels

  # Says who it is drawn for, the way a per-visitor block decides by `current_user` and `viewer`.
  @block ~s(<div id={@id} data-role="acme-library" data-viewer={@viewer} data-who={if @current_user, do: @current_user.email, else: "nobody"}>{@heading}</div>)

  setup %{site: site} do
    create_component!(
      name: "acme-library",
      site_id: site.id,
      template: @block,
      extra: %{"label" => "Acme library"},
      attrs: [
        %{"name" => "id", "type" => "string", "opts" => %{"default" => "acme"}},
        %{
          "name" => "product",
          "type" => "any",
          "opts" => %{
            "default" => "",
            "group" => "Product",
            "label" => "Which product",
            "editor" => "select",
            "choices" => "acme:products"
          }
        },
        %{
          "name" => "look",
          "type" => "string",
          "opts" => %{
            "default" => "light",
            "group" => "Style",
            "values" => ["light", "dark"],
            "labels" => %{"light" => "Light (follows the site)", "dark" => "Dark"}
          }
        },
        %{
          "name" => "viewer",
          "type" => "string",
          "opts" => %{
            "default" => "auto",
            "group" => "Viewer",
            "label" => "Preview as",
            "canvas_only" => true,
            "values" => ["auto", "owner"]
          }
        },
        %{"name" => "heading", "type" => "string", "opts" => %{"default" => "Yours"}},
        %{"name" => "current_user", "type" => "any", "opts" => %{"default" => nil}}
      ]
    )

    :ok = AttrChoices.forget()
    on_exit(&AttrChoices.forget/0)
    :ok
  end

  defp page_with!(site, attrs) do
    create_page!(
      site_id: site.id,
      template:
        ~s(<section id="shop"><.component component_name="acme-library" site="localhost" id="lib" #{attrs} /></section>)
    )
  end

  defp live_template(page) do
    {:ok, page} =
      Ash.get(MishkaCmsCore.Runtime.Page, page.id, action: :master_get, authorize?: false)

    page.template
  end

  defp inspect_block(view) do
    node =
      view
      |> editor()
      |> Map.fetch!(:tree)
      |> Tree.walk()
      |> Enum.find(&(Node.component_name(&1) == "acme-library"))

    render_click(view, "select", %{"id" => node.id})
    render_click(view, "set_left_tab", %{"tab" => "inspector"})
    node
  end

  test "the Inspector draws the kit's sections, words and read choices, and not the visitor",
       %{conn: conn, site: site} do
    register_plugin(ChoicesPlugin, "builder:attr:choices")
    {:ok, view, _html} = open_builder(conn, page_with!(site, ~s(product="icon-set")))
    node = inspect_block(view)
    html = render(view)

    assert html =~ "Which product"

    assert has_element?(
             view,
             ~s(#pb-attr-#{node.id}-product option[value="photo-pack"]),
             "Photo pack"
           )

    assert has_element?(view, ~s(#pb-attr-#{node.id}-product option[selected]), "Icon set")
    assert has_element?(view, ~s(#pb-attr-#{node.id}-look option), "Light (follows the site)")
    assert has_element?(view, ~s(#pb-attr-#{node.id}-viewer [data-role="pb-attr-canvas-only"]))
    refute has_element?(view, ~s(#pb-attr-#{node.id}-current_user))

    [product, look, viewer] =
      for name <- ~w(product look viewer), do: :binary.match(html, "pb-attr-#{node.id}-#{name}")

    assert product < look and look < viewer
  end

  test "with nothing to read, the choice is a text box", %{conn: conn, site: site} do
    {:ok, view, _html} = open_builder(conn, page_with!(site, ~s(product="icon-set")))
    node = inspect_block(view)

    refute has_element?(view, ~s(#pb-attr-#{node.id}-product select))
    assert has_element?(view, ~s(#pb-attr-#{node.id}-product input))
  end

  test "a publish hands the block the page's visitor and leaves the canvas choice out",
       %{conn: conn, site: site} do
    page = page_with!(site, ~s(viewer="owner" heading="Mine"))
    {:ok, view, _html} = open_builder(conn, page)

    render_click(view, "publish_now", %{})

    template = live_template(page)
    assert template =~ "current_user={assigns[:current_user]}"
    assert template =~ ~s(heading="Mine")
    refute template =~ "viewer"

    # The canvas still draws what the author picked.
    assert view
           |> editor()
           |> Map.fetch!(:tree)
           |> Tree.walk()
           |> Enum.any?(fn node ->
             Node.attr_text(node, "viewer") == "owner"
           end)
  end

  defp source_shown(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#pb-source-copy")
    |> LazyHTML.attribute("data-copy")
    |> List.first()
  end

  defp canvas_html(conn, view) do
    {:ok, _canvas, html} = live(conn, "/admin/dashboard/runtime/builder-canvas/#{token(view)}")
    html
  end

  defp who(html),
    do:
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s([data-role="acme-library"]))
      |> LazyHTML.attribute("data-who")

  test "the Code window shows what a save writes, not the canvas's draft",
       %{conn: conn, site: site} do
    page = page_with!(site, ~s(viewer="owner" heading="Mine"))
    {:ok, view, _html} = open_builder(conn, page)

    render_click(view, "open_source", %{"tab" => "template"})
    shown = source_shown(view)

    assert shown =~ "current_user={assigns[:current_user]}"
    assert shown =~ ~s(heading="Mine")
    refute shown =~ "viewer"

    render_click(view, "publish_now", %{})
    assert String.trim(live_template(page)) == String.trim(shown)
  end

  test "applying the Code window unchanged keeps the canvas's own choice",
       %{conn: conn, site: site} do
    {:ok, view, _html} = open_builder(conn, page_with!(site, ~s(viewer="owner")))

    render_click(view, "open_source", %{"tab" => "template"})
    render_submit(view, "apply_source", %{"source" => source_shown(view)})

    assert view
           |> editor()
           |> Map.fetch!(:tree)
           |> Tree.walk()
           |> Enum.any?(&(Node.attr_text(&1, "viewer") == "owner"))
  end

  test "a draft kept on the way out is written as a save writes it", %{conn: conn, site: site} do
    page = page_with!(site, ~s(viewer="owner"))
    {:ok, view, _html} = open_builder(conn, page)
    recorded = actor(view)
    render_click(view, "set_stage", %{"stage" => "published"})
    node = inspect_block(view)

    render_click(view, "op", %{
      "kind" => "set_attr",
      "node_id" => node.id,
      "name" => "heading",
      "value" => "Changed"
    })

    render_click(view, "leaving", %{"to" => "/admin/dashboard"})
    render_click(view, "draft_and_leave", %{})

    [kept] = Drafts.list("page", page, recorded)
    assert kept.template =~ "current_user={assigns[:current_user]}"
    assert kept.template =~ ~s(heading="Changed")
    refute kept.template =~ "viewer"
  end

  test "the canvas draws a per-visitor block for the person editing it",
       %{conn: conn, site: site} do
    {:ok, view, _html} = open_builder(conn, page_with!(site, ~s(heading="Mine")))
    email = to_string(actor(view).email)

    assert who(canvas_html(conn, view)) == [email]
  end

  test "a block's own Preview as still decides who it is drawn for", %{conn: conn, site: site} do
    {:ok, view, _html} = open_builder(conn, page_with!(site, ~s(viewer="owner")))

    html = canvas_html(conn, view)

    assert html
           |> LazyHTML.from_fragment()
           |> LazyHTML.query(~s([data-role="acme-library"]))
           |> LazyHTML.attribute("data-viewer") == ["owner"]
  end

  test "a kit's own name for a component is its card's whole label" do
    prefixes = MapSet.new(["acme"])

    assert Panels.short_label(
             %{name: "acme-library", label: "Acme library", titled?: true},
             prefixes
           ) ==
             "Acme library"

    assert Panels.short_label(%{name: "acme-library", label: "Acme Library"}, prefixes) ==
             "Library"
  end
end
