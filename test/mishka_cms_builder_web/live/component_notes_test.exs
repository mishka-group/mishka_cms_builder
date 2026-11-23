# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.ComponentNotesTest do
  @moduledoc """
  What an extension says about a placed block reaches the author in the editor's three places: the
  canvas frame (`data-pb-note` and the `pb-component-note` badge), the Inspector (`pb-insp-note`)
  and the Audit rail (the Content group), and nowhere when no extension has anything to say.

  It does NOT prove what a real extension judges (each extension's own plugin tests that), or that
  a published page never asks: the published page does not run the editor's code, which is the
  whole of that proof.
  """
  use MishkaCmsBuilder.LiveCase

  alias MishkaCmsBuilder.ComponentNotes
  alias MishkaCmsBuilder.Test.Plugins.BuilderComponentNotesPlugin, as: NotesPlugin

  @block ~s(<div id={@id} data-role="acme-product">{@product}</div>)

  setup %{site: site} do
    create_component!(
      name: "acme-product",
      site_id: site.id,
      template: @block,
      attrs: [
        %{"name" => "id", "type" => "string", "opts" => %{"default" => "acme"}},
        %{"name" => "product", "type" => "string", "opts" => %{"default" => ""}}
      ]
    )

    :ok = ComponentNotes.forget()
    on_exit(&ComponentNotes.forget/0)
    :ok
  end

  defp page_with!(site, products) do
    blocks =
      products
      |> Enum.with_index()
      |> Enum.map_join(fn {product, at} ->
        ~s(<.component component_name="acme-product" site="localhost" id="p#{at}" product="#{product}" />)
      end)

    create_page!(site_id: site.id, template: ~s(<section id="shop">#{blocks}</section>))
  end

  defp block_node(view) do
    view
    |> editor()
    |> Map.fetch!(:tree)
    |> Tree.walk()
    |> Enum.find(&(Node.component_name(&1) == "acme-product"))
  end

  defp canvas_html(conn, view) do
    {:ok, _canvas, html} = live(conn, "/admin/dashboard/runtime/builder-canvas/#{token(view)}")
    html
  end

  describe "with an extension that has a note for the block" do
    setup do
      register_plugin(NotesPlugin, "builder:component:notes")
      :ok
    end

    test "the Audit rail lists it under Content, pointing at the block", %{conn: conn, site: site} do
      {:ok, view, _html} = open_builder(conn, page_with!(site, ["gone"]))
      render_click(view, "set_right_tab", %{"tab" => "audit"})

      assert has_element?(view, "#pb-audit-group-content", "The product gone was archived.")
      assert has_element?(view, "#pb-audit-group-content", "Visitors see nothing in this block.")

      assert has_element?(
               view,
               ~s(#pb-audit-group-content button[phx-value-id="#{block_node(view).id}"])
             )

      refute has_element?(view, ~s(#pb-audit-group-content [id^="pb-audit-fix-component-note"]))
    end

    test "the Inspector shows it under the selected block's name", %{conn: conn, site: site} do
      {:ok, view, _html} = open_builder(conn, page_with!(site, ["gone"]))
      render_click(view, "select", %{"id" => block_node(view).id})
      render_click(view, "set_left_tab", %{"tab" => "inspector"})

      assert has_element?(
               view,
               ~s([data-role="pb-insp-note"][data-severity="warning"]),
               "The product gone was archived."
             )
    end

    test "the canvas frame carries the note and its badge", %{conn: conn, site: site} do
      {:ok, view, _html} = open_builder(conn, page_with!(site, ["gone"]))
      html = canvas_html(conn, view)

      assert html =~ ~r/<div[^>]*data-pb-note="warning"/

      assert html =~
               ~r/<span[^>]*data-role="pb-component-note"[^>]*>The product gone was archived\./
    end

    test "a block whose product is fine has no note anywhere", %{conn: conn, site: site} do
      {:ok, view, _html} = open_builder(conn, page_with!(site, ["photo-pack"]))
      render_click(view, "set_right_tab", %{"tab" => "audit"})

      refute has_element?(view, "#pb-audit-group-content")
      refute canvas_html(conn, view) =~ ~s(data-pb-note=")
    end

    test "the same block asked again in a burst of renders is asked once, and again after forget",
         %{site: site} do
      Process.register(self(), NotesPlugin.waiter())
      {:ok, tree} = Tree.parse(page_with!(site, ["gone"]).template)
      [block] = tree |> Tree.walk() |> Enum.filter(&(&1.kind == :component))
      scope = %{site_id: site.id, site_name: site.name}

      assert [%{severity: :warning}] = ComponentNotes.for_node(block, scope)
      assert [%{severity: :warning}] = ComponentNotes.for_node(block, scope)

      site_id = site.id
      assert_received {NotesPlugin, "acme-product", %{"product" => "gone"}, ^site_id}
      refute_received {NotesPlugin, _component, _attrs, _site}

      :ok = ComponentNotes.forget()
      assert [%{severity: :warning}] = ComponentNotes.for_node(block, scope)
      assert_received {NotesPlugin, "acme-product", %{"product" => "gone"}, ^site_id}
    end
  end

  test "with no extension listening nothing is drawn", %{conn: conn, site: site} do
    {:ok, view, _html} = open_builder(conn, page_with!(site, ["gone"]))
    render_click(view, "set_right_tab", %{"tab" => "audit"})

    refute has_element?(view, "#pb-audit-group-content")
    refute has_element?(view, ~s([data-role="pb-insp-note"]))
    refute canvas_html(conn, view) =~ ~s(data-pb-note=")
  end

  test "the attributes an extension is handed are the literal ones" do
    {:ok, tree} =
      Tree.parse(
        ~s(<.component component_name="acme-product" site="localhost" product="photo-pack" limit={6} wide show={false} slug={@query_params["slug"]} />)
      )

    [node] = tree |> Tree.walk() |> Enum.filter(&(&1.kind == :component))

    assert ComponentNotes.attrs(node) == %{
             "site" => "localhost",
             "product" => "photo-pack",
             "limit" => 6,
             "wide" => true,
             "show" => false
           }
  end
end
