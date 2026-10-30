# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.BuilderLive.PublishFlowTest do
  @moduledoc """
  Publishing is one click from the stage menu, and the menu says what each of its choices does.

  The menu used to offer "Published" and "Draft". Choosing "Published" did not publish: it switched
  the editor into Publish mode, which stops the draft, and a banner said changes were "recorded but
  not saved to the page". The button that publishes appeared only after that. Now the menu leads with
  Publish now, names the two modes as modes, and the Publish mode bar carries a Publish button.
  What publishing writes is unchanged, and so is the question asked when leaving Publish mode with
  work on screen.
  """
  use MishkaCmsBuilder.LiveCase

  defp live_template(page) do
    {:ok, page} =
      Ash.get(MishkaCmsCore.Runtime.Page, page.id, action: :master_get, authorize?: false)

    page.template
  end

  defp edit!(view),
    do: render_click(view, "op", %{"kind" => "delete", "node_id" => node_with_tag(view, "p").id})

  test "Publish now puts the work on the live page from Draft mode", %{conn: conn, page: page} do
    {:ok, view, _html} = open_builder(conn, page)
    edit!(view)

    html = view |> element("#pb-stage-publish-now") |> render_click()

    refute live_template(page) =~ "Reach out any time."
    assert live_template(page) =~ "Contact Us"
    assert html =~ "Page published."

    # The screen is the live page now, so the menu has nothing new to publish.
    refute has_element?(view, "#pb-stage-publish-now")
  end

  test "the menu names the two modes and says what each does", %{conn: conn, page: page} do
    {:ok, view, _html} = open_builder(conn, page)
    menu = view |> element("#pb-stage-ways") |> render()

    assert menu =~ "Publish now"
    assert menu =~ "Publish mode"
    assert menu =~ "Nothing goes live until you press Publish."
    assert menu =~ "Draft mode"
    assert menu =~ "Saves a draft as you work."
  end

  test "choosing Publish mode says how the work goes live", %{conn: conn, page: page} do
    {:ok, view, _html} = open_builder(conn, page)

    html = render_click(view, "set_stage", %{"stage" => "published"})

    assert html =~ "Press Publish to put your changes on the live page"
    refute html =~ "recorded but not saved to the page"
  end

  test "the Publish mode bar publishes from where it says so", %{conn: conn, page: page} do
    {:ok, view, _html} = open_builder(conn, page)
    render_click(view, "set_stage", %{"stage" => "published"})
    edit!(view)

    assert view |> element("#pb-publish-bar") |> render() =~ "Publish puts them live"

    view |> element("#pb-publish-bar-publish") |> render_click()

    refute live_template(page) =~ "Reach out any time."
    refute has_element?(view, "#pb-publish-bar")
  end

  test "leaving Publish mode with work on screen still asks", %{conn: conn, page: page} do
    {:ok, view, _html} = open_builder(conn, page)
    render_click(view, "set_stage", %{"stage" => "published"})
    edit!(view)

    render_click(view, "leaving", %{"to" => "/admin/dashboard/runtime/pages"})

    assert has_element?(view, "#pb-leave-publish")
    assert has_element?(view, "#pb-leave-save")
  end
end
