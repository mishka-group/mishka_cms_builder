# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.RuntimeInspectorModalTest do
  @moduledoc """
  The Visual Editor link in the modal every runtime table opens.

  The modal is the core's, and so is every other control in it. The link is the editor's: the core
  asks `runtime:document:editor_url` and the editor's plugin answers, so a host without the editor
  draws none. Here the editor is installed, and an admin who may write the record's section, or who
  holds code, is offered it.
  """
  use MishkaCmsBuilder.LiveCase, async: false

  @await 5_000

  # THE BUILDER OPENS FOR ITS OWN TYPE'S SECTION OR CODE, which `BuilderLive` asks again.
  for names <- [["admin:dashboard:runtime:page"], ["admin:dashboard:code"]] do
    @names names

    test "#{Enum.join(names, " + ")} is offered the Visual Editor", %{site: site, page: page} do
      {:ok, view, _html} = live(narrow_conn(site, @names), "/admin/dashboard/runtime/pages")
      send(view.pid, {:row_action, "show_preview_modal", %{"id" => page.id}})

      assert render_async(view, @await) =~ page.name, "the modal did not finish opening"
      assert render(view) =~ "Visual Editor"
    end
  end
end
