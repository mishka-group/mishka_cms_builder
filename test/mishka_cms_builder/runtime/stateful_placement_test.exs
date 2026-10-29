# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Runtime.StatefulPlacementTest do
  @moduledoc """
  Where a live component may go, and the three places it may not.

  A stateful component compiles to a `Phoenix.LiveComponent`, and calling one produces a
  `%Phoenix.LiveView.Component{}` — a token only a LiveView's diff turns into HTML. Three of the four
  things this runtime compiles are rendered where no such diff runs, and each failure is silent
  rather than loud:

    * an ERROR PAGE is served by a controller (`ErrorHTML.render/2` calls
      `page_module.render(conn, status)`), the token raises inside that function's own rescue, and
      the site's custom error page is replaced by Phoenix's plain default for every visitor
    * a LAYOUT wraps error pages, so it inherits it
    * ANOTHER COMPONENT's template is drawn by the canvas through `contain/3`, and the token blows up
      the PARENT's containment — a red chip on a component the author did not touch

  A page is a LiveView end to end, which is why a page is the one surface that may hold one.
  """
  use MishkaCmsCore.DataCase
  use ExUnit.Case, async: false

  require Ash.Query

  @moduletag :integration

  defp live_component!(site, name \\ "live-widget") do
    create_component!(
      name: name,
      site_id: site.id,
      stateful: true,
      template: ~s(<div id={@id} {@rest}>live</div>),
      attrs: [%{"name" => "rest", "type" => "global", "opts" => %{}}]
    )
  end

  # THE DUPLICATE-ID RULE. `Phoenix.LiveView.Diff` raises "found duplicate ID … for component …"
  # inside whichever LiveView renders the page, where nothing contains it — so this is a rule and
  # not a finding.
  #
  # The editor's own minting does not cover it: `Ids.dedupe/2` renames the nodes that ARRIVED and
  # answers nothing when a whole document arrives at once, which is exactly what the source window,
  # a draft restore and a seeded template do.
  describe "two live components under one id" do
    defp page(site, template) do
      MishkaCmsCore.Runtime.Page
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: "ids-#{System.unique_integer([:positive])}",
          title: "Ids",
          path: "/ids-#{System.unique_integer([:positive])}",
          template: template
        },
        tenant: site.id,
        context: %{page_code: :package}
      )
      |> Ash.create(authorize?: false)
    end

    defp twice(name, id_one, id_two) do
      ~s(<div><.component component_name="#{name}" site="Global" id="#{id_one}" />) <>
        ~s(<.component component_name="#{name}" site="Global" id="#{id_two}" /></div>)
    end

    # AND AN AUTHOR SHOULD NEVER MEET THAT REFUSAL BY DUPLICATING ONE, which is the ordinary way to
    # get a second of anything. `Tree.duplicate/2` copies every attribute verbatim, so the copy
    # arrives wearing the original's id; `Ids.dedupe/2` renames the node that ARRIVED and leaves the
    # one already placed alone. Nothing about that mechanism is specific to live components — which
    # is exactly why it is pinned here, where getting it wrong means a save the author cannot
    # complete rather than two buttons opening one dialog.
    test "a duplicate arrives with an id of its own, so the rule is never met" do
      alias MishkaCmsBuilder.Ids
      alias MishkaCmsCore.Runtime.PageBuilder.Tree

      {:ok, tree} = Tree.parse(twice("live-widget", "phx-F8kQ2n1aRxY", "phx-F8kQ2n1aRxY"))

      [_original, copy] = Tree.walk(tree) |> Enum.filter(&(&1.kind == :component))

      ids =
        tree
        |> Ids.dedupe([copy.id])
        |> Tree.walk()
        |> Enum.filter(&(&1.kind == :component))
        |> Enum.map(&Tree.Node.attr(&1, "id"))

      assert [{:string, "phx-F8kQ2n1aRxY"}, {:string, fresh}] = ids

      assert fresh != "phx-F8kQ2n1aRxY",
             "the copy kept the original's id — every duplicate would be a save the author cannot complete"
    end

    test "is refused, with both named" do
      site = create_site!()
      _live = live_component!(site)

      assert {:error, error} = page(site, twice("live-widget", "same", "same"))

      message = Exception.message(error)
      assert message =~ "same"
      assert message =~ "live-widget"
      assert message =~ "give each its own"
    end

    test "and two with their own ids are fine" do
      site = create_site!()
      _live = live_component!(site)

      assert {:ok, _page} = page(site, twice("live-widget", "one", "two"))
    end

    # A FUNCTION COMPONENT SHARING AN ID IS A BAD IDEA AND NOT A CRASH, and the editor already
    # renames those. This rule is about the one that takes the page down.
    test "and two function components sharing one are not this rule's business" do
      site = create_site!()
      _plain = create_component!(name: "plain-widget", site_id: site.id)

      assert {:ok, _page} = page(site, twice("plain-widget", "same", "same"))
    end

    # `id={@row.id}` IS THE AUTHOR BINDING THE ID TO THEIR DATA, and two of them are not a
    # collision — the same distinction `MishkaCmsBuilder.Ids` draws.
    test "and an expression is not a literal this can compare" do
      site = create_site!()
      _live = live_component!(site)

      template =
        ~s(<div><.component component_name="live-widget" site="Global" id={@a} />) <>
          ~s(<.component component_name="live-widget" site="Global" id={@b} /></div>)

      assert {:ok, _page} = page(site, template)
    end
  end
end
