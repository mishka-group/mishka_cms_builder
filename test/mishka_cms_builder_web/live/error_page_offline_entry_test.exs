# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.ErrorPageOfflineEntryTest do
  @moduledoc """
  The offline page in the Error Pages admin, as the visual editor adds it: the editor opens a status
  the row lacks empty, and saving what is built there writes the entry beside the others. The form
  that offers the status and the preview's picker are asserted in the core.

  Its own file: nothing else drives the Error Pages index as a LiveView.
  """
  use MishkaCmsCore.ConnCase

  import Phoenix.LiveViewTest
  import MishkaCmsCore.Test.Factory

  alias MishkaCmsCore.Accounts.{Permission, User, UserPermission}
  alias MishkaCmsCore.Runtime.{ErrorAddress, ErrorPage}
  alias MishkaCmsCore.Runtime.States.SiteState

  require Ash.Query

  @password "Password123!"

  setup %{conn: conn} do
    SiteState.clear()
    site = create_site!(name: "localhost", host: "localhost", active: true, master: true)

    SiteState.save(%{
      id: site.id,
      name: site.name,
      host: site.host,
      priority: site.priority,
      active: site.active,
      master: site.master
    })

    :persistent_term.put(:mishka_installed, true)
    on_exit(fn -> :persistent_term.erase(:mishka_installed) end)

    conn =
      conn
      |> Map.put(:host, "localhost")
      |> Map.update!(:req_headers, &[{"host", "localhost"} | List.keydelete(&1, "host", 0)])
      |> log_in(create_admin("tenant@example.com", site.id))

    row =
      ErrorPage
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: "localhost errors",
          path: ErrorAddress.path(site.name),
          error_pages: [
            %{status: 404, template: "<p>Not here</p>"},
            %{status: 500, template: "<p>Broke</p>"}
          ]
        },
        tenant: site.id,
        authorize?: false
      )
      |> Ash.create!()

    {:ok, conn: conn, site: site, row: row}
  end

  defp star_permission do
    Permission
    |> Ash.Query.filter(name == "*")
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil -> create_permission!(name: "*")
      permission -> permission
    end
  end

  defp create_admin(email, site_id) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_create(
        :register_with_password,
        %{email: email, password: @password, password_confirmation: @password},
        authorize?: false
      )
      |> Ash.Changeset.set_tenant(site_id)
      |> Ash.create()

    UserPermission
    |> Ash.Changeset.for_create(:assign, %{}, authorize?: false)
    |> Ash.Changeset.force_change_attribute(:user_id, user.id)
    |> Ash.Changeset.force_change_attribute(:permission_id, star_permission().id)
    |> Ash.create!(authorize?: false)

    user
  end

  defp log_in(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:master_mode, true)
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end

  defp stored(row), do: Ash.get!(ErrorPage, row.id, tenant: row.site_id, authorize?: false)

  # The builder opens a status the row lacks empty, and saving what is built there writes the entry
  # beside the others.
  test "the builder adds the offline page beside the row's entries", %{conn: conn, row: row} do
    {:ok, builder, _html} = live(conn, "/admin/dashboard/runtime/builder/error-page/#{row.id}")
    refute has_element?(builder, "#pb-status-offline")

    assert {:error, {:live_redirect, %{to: to}}} =
             builder |> element("#pb-status-add-offline") |> render_click()

    {:ok, builder, _html} = live(conn, to)
    assert has_element?(builder, "#pb-status-offline")

    render_click(builder, "drop", %{
      "template" => "<h1>Back soon</h1>",
      "parent_id" => "root",
      "index" => "0"
    })

    render_click(builder, "publish", %{})

    assert Map.new(stored(row).error_pages, &{&1.status, &1.template}) |> Map.take([404, 500]) ==
             %{404 => "<p>Not here</p>", 500 => "<p>Broke</p>"}

    assert Enum.find(stored(row).error_pages, &(&1.status == :offline)).template =~ "Back soon"
  end
end
