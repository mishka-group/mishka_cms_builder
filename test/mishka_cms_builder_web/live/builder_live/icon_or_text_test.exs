# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.BuilderLive.IconOrTextTest do
  @moduledoc """
  A label that is an icon or words.

  `chelekom-pagination` declares `previous_label`, `next_label`, `first_label`, `last_label` and
  `separator` as maps, each defaulting to `%{type: :icon, value: "hero-chevron-right"}` and each
  rendered as an icon when its `type` is `:icon` and as words otherwise. The Inspector gave them
  the icon control alone, and its box writes what is typed as the icon's name: the palette sweep
  typed `E2E-4` into `next_label`, the canvas lost the next arrow, and the console logged
  `chelekom-icon's body did not apply: no match of right hand side value: %{name: "E2E-4", ...}`.

  The component is a copy of the styled kit's own row from the committed bundle.
  """
  use MishkaCmsBuilder.LiveCase

  @placed ~S|<.component component_name="chelekom-pagination" site="localhost" total={8} />|

  setup %{site: site} do
    row =
      MishkaCmsCore.Runtime.Handlers.UiKitHandler.default_bundle_path()
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("components")
      |> Enum.find(&(&1["name"] == "chelekom-pagination"))

    create_component!(
      name: row["name"],
      site_id: site.id,
      template: row["template"],
      attrs: row["attrs"],
      slots: row["slots"],
      helpers: row["helpers"]
    )

    %{pager: create_page!(site_id: site.id, template: @placed)}
  end

  defp pager(conn, page) do
    {:ok, view, _html} = open_builder(conn, page)
    node = placed(view)

    render_click(view, "set_left_tab", %{"tab" => "inspector"})
    render_click(view, "select", %{"id" => node.id})
    {view, node}
  end

  defp placed(view),
    do: Enum.find(Tree.walk(editor(view).tree), &(&1.kind == :component))

  defp held(view, name) do
    case view |> placed() |> Node.attr(name) do
      {:expr, source} -> source |> Code.eval_string() |> elem(0)
      other -> other
    end
  end

  describe "a label that is an icon or words" do
    test "offers both, and starts on the one its value holds", %{conn: conn, pager: page} do
      {view, node} = pager(conn, page)

      assert has_element?(view, "#pb-label-kind-#{node.id}-next_label-icon[aria-pressed=true]")
      assert has_element?(view, "#pb-label-kind-#{node.id}-next_label-text[aria-pressed=false]")
      assert has_element?(view, "#pb-icon-form-#{node.id}-next_label")
    end

    # THE REPORTED DEFECT: words typed into the icon's box became the icon's name.
    test "words typed where an icon goes are not written as one", %{conn: conn, pager: page} do
      {view, node} = pager(conn, page)

      view
      |> element("#pb-icon-form-#{node.id}-next_label")
      |> render_change(%{"value" => "E2E-4"})

      assert held(view, "next_label") == nil

      view
      |> element("#pb-icon-form-#{node.id}-next_label")
      |> render_change(%{"value" => "hero-arrow-right"})

      assert held(view, "next_label") == %{type: :icon, value: "hero-arrow-right"}
    end

    test "Text makes it words, written in the shape the component reads", %{
      conn: conn,
      pager: page
    } do
      {view, node} = pager(conn, page)

      view |> element("#pb-label-kind-#{node.id}-next_label-text") |> render_click()

      assert held(view, "next_label") == %{type: :text, value: "Next"}
      assert has_element?(view, "#pb-label-text-form-#{node.id}-next_label")
      refute has_element?(view, "#pb-icon-form-#{node.id}-next_label")

      view
      |> element("#pb-label-text-form-#{node.id}-next_label")
      |> render_change(%{"value" => "E2E-4"})

      assert held(view, "next_label") == %{type: :text, value: "E2E-4"}
    end

    test "and Icon makes it the component's own icon again", %{conn: conn, pager: page} do
      {view, node} = pager(conn, page)

      view |> element("#pb-label-kind-#{node.id}-next_label-text") |> render_click()
      view |> element("#pb-label-kind-#{node.id}-next_label-icon") |> render_click()

      assert held(view, "next_label") == %{type: :icon, value: "hero-chevron-right"}
    end

    test "clearing the words gives the component its default back", %{conn: conn, pager: page} do
      {view, node} = pager(conn, page)

      view |> element("#pb-label-kind-#{node.id}-next_label-text") |> render_click()

      view
      |> element("#pb-label-text-form-#{node.id}-next_label")
      |> render_change(%{"value" => ""})

      assert held(view, "next_label") == nil
    end
  end
end
