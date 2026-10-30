# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.PartPlacementTest do
  @moduledoc """
  A kit's part dropped where its parent does not hold it, from the palette's own read of the kit's
  catalogue to the drop — see `MishkaCmsBuilder.PartPlacement`.

  An e2e run dropped Chelekom's Card Footer on a navbar and it landed in the navbar's
  `:end_content` slot as a padded box.
  """
  use MishkaCmsBuilder.LiveCase

  alias MishkaCmsBuilder.PartPlacement

  @bundle MishkaCmsCore.Runtime.Handlers.UiKitHandler.default_bundle_path()

  @names ~w(chelekom-card chelekom-card-footer chelekom-navbar)

  # The kit's rows as the bundle ships them, `extra` and all: what an install writes.
  # sobelow_skip ["Traversal.FileModule"]
  setup_all do
    rows =
      @bundle
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("components")
      |> Enum.filter(&(&1["name"] in @names))

    {:ok, rows: rows}
  end

  defp install!(site, rows) do
    for row <- rows do
      create_component!(
        site_id: site.id,
        name: row["name"],
        template: row["template"],
        attrs: row["attrs"] || [],
        slots: row["slots"] || [],
        extra: row["extra"] || %{}
      )
    end
  end

  defp named(view, name),
    do:
      view
      |> editor()
      |> Map.fetch!(:tree)
      |> Tree.walk()
      |> Enum.filter(&(Node.component_name(&1) == name))

  @footer ~s(<.component component_name="chelekom-card-footer" site="localhost">Read more</.component>)

  test "the palette reads which component a kit's part belongs in out of the kit itself", %{
    conn: conn,
    site: site,
    rows: rows
  } do
    install!(site, rows)
    page = create_page!(site_id: site.id, template: ~s(<main id="root"></main>))
    {:ok, view, _html} = open_builder(conn, page)

    components = editor(view).components
    footer = Enum.find(components, &(&1.name == "chelekom-card-footer"))

    assert footer.kit_family == "card"
    assert [_ | _] = footer.example_heads
    assert Enum.all?(footer.example_heads, &(&1 == "chelekom-card"))

    assert PartPlacement.holder("chelekom-card-footer", components).name == "chelekom-card"
    assert PartPlacement.holder("chelekom-card", components) == nil
    assert PartPlacement.holder("chelekom-navbar", components) == nil
  end

  test "a Card Footer dropped in a navbar's slot arrives in a new Card there", %{
    conn: conn,
    site: site,
    rows: rows
  } do
    install!(site, rows)

    page =
      create_page!(
        site_id: site.id,
        template:
          ~s(<main id="root"><.component component_name="chelekom-navbar" site="localhost"><:end_content><span>Menu</span></:end_content></.component></main>)
      )

    {:ok, view, _html} = open_builder(conn, page)

    slot =
      view |> editor() |> Map.fetch!(:tree) |> Tree.walk() |> Enum.find(&(&1.kind == :slot))

    render_hook(view, "drop", %{"template" => @footer, "parent_id" => slot.id, "index" => 0})

    assert render(view) =~ "Card Footer goes inside Card, so it arrived in a new one."
    assert [footer] = named(view, "chelekom-card-footer")
    assert [card] = named(view, "chelekom-card")
    assert footer.parent_id == card.id
    assert card.parent_id == slot.id
  end
end
