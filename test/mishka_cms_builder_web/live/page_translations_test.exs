# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.PageTranslationsTest do
  @moduledoc """
  The pages table with translated pages in it, driven through the real page.

  A translation is a page row of its own, so a list of rows would show "about" beside "about-fa" —
  the same page twice. The table shows one row per page and a chip for each other language, a search
  lifts that so a Persian title can be found, and a row's "Add translation" makes the next edition
  through the page's own create action. A master's Delete, one row or a bulk selection, is refused
  while a live translation remains, its Delete permanently too, and a translation's Restore is
  refused while its master is archived — each time with the admin told why. A refused Delete comes
  with a button that archives, or deletes for good, those translations at once.

  See `MishkaCmsCore.Runtime.PageEditions` and `MishkaCmsCore.LanguageEditions`.
  """
  use MishkaCmsCore.ConnCase

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import MishkaCmsCore.Test.Factory

  alias MishkaCmsCore.Accounts.{Permission, User, UserPermission}
  alias MishkaCmsCore.Runtime.States.SiteState
  alias MishkaCmsCore.Settings

  require Ash.Query

  @password "Password123!"
  @url "/admin/dashboard/runtime/pages"
  @await 5_000

  setup %{conn: conn} do
    SiteState.clear()
    Application.put_env(:ash_json_api, MishkaCmsCore.Accounts, router: MishkaCmsWeb.Router)

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

    on_exit(fn ->
      :persistent_term.erase(:mishka_installed)
      SiteState.clear()
    end)

    MishkaCmsCore.DataCase.forget_settings(~w(site.languages), [site.id])
    {:ok, _} = Settings.put("site.languages", ["en", "fa", "ar"], site_id: site.id)

    n = System.unique_integer([:positive])
    master = create_page!(site_id: site.id, name: "about-#{n}", path: "/about-#{n}")

    admin = create_admin("translations-#{n}@example.com")

    conn =
      conn
      |> Map.put(:host, "localhost")
      |> Map.update!(:req_headers, &[{"host", "localhost"} | List.keydelete(&1, "host", 0)])
      |> log_in(admin)

    {:ok, conn: conn, site: site, master: master, admin: admin}
  end

  defp translate!(site, master, language, overrides \\ []) do
    create_page!(
      [
        site_id: site.id,
        name: "#{master.name}-#{language}",
        path: "/#{language}#{master.path}",
        language: language,
        language_group_id: master.id
      ] ++ overrides
    )
  end

  defp open_pages(conn) do
    {:ok, view, _html} = live(conn, @url)
    render_async(view, @await)
    view
  end

  defp chip(page), do: "#page-edition-#{page.id}"

  @act "#translations-refusal-act"

  defp act(view) do
    view |> element(@act) |> render_click()
    view
  end

  describe "the list" do
    test "a chip opens that edition", %{conn: conn, site: site, master: master} do
      fa = translate!(site, master, "fa")
      view = open_pages(conn)

      view |> element(chip(fa)) |> render_click()
      render_async(view, @await)

      assert has_element?(
               view,
               ~s(#runtime-preview-modal a[href^="/admin/dashboard/runtime/builder/page/#{fa.id}?"])
             ),
             "the chip did not open the Persian edition"
    end
  end

  defp permission!(name) do
    case Permission |> Ash.Query.filter(name == ^name) |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        Permission
        |> Ash.Changeset.for_create(:create, %{name: name}, authorize?: false)
        |> Ash.create!()

      {:ok, permission} ->
        permission
    end
  end

  defp create_admin(email, site_id \\ nil) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_create(
        :register_with_password,
        %{email: email, password: @password, password_confirmation: @password},
        authorize?: false
      )
      |> then(&if(site_id, do: Ash.Changeset.set_tenant(&1, site_id), else: &1))
      |> Ash.create()

    UserPermission
    |> Ash.Changeset.for_create(:assign, %{}, authorize?: false)
    |> Ash.Changeset.force_change_attribute(:user_id, user.id)
    |> Ash.Changeset.force_change_attribute(:permission_id, permission!("*").id)
    |> Ash.create!(authorize?: false)

    user
  end

  defp log_in(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:master_mode, true)
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end
end
