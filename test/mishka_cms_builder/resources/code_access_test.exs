# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Resources.CodeAccessTest do
  @moduledoc """
  Who may write code by hand, and when this deployment takes it.

  Code is Elixir (`events`, `infos`, `helpers`), hand-written HEEx (`template`,
  `root_layout_template`, an error page's status templates), and browser code (a JS hook's or a
  stylesheet's `content`). Whoever may write the record writes its code; the deployment's
  `:page_code` switch, enforced at the action boundary, stops the Elixir and the typed HEEx for
  everyone.
  """
  use MishkaCmsCore.DataCase, async: false

  require Ash.Query

  import MishkaCmsCore.Test.Factory

  alias MishkaCmsCore.Accounts.{Permission, User, UserPermission}
  alias MishkaCmsCore.Runtime.PageBuilder.CodeAccess

  @moduletag :integration
  @moduletag :capture_log

  @password "Password123!"
  @handler [%{"name" => "save", "code" => "{:noreply, socket}"}]

  setup do
    site = create_site!(name: "code-gate", host: "code-gate.test", active: true)
    on_exit(fn -> Application.delete_env(:mishka_cms_core, :page_code) end)
    {:ok, site: site}
  end

  defp permission!(name) do
    case Permission |> Ash.Query.filter(name == ^name) |> Ash.read_one(authorize?: false) do
      {:ok, %Permission{} = permission} ->
        permission

      _none ->
        Permission
        |> Ash.Changeset.for_create(:create, %{name: name, description: name}, authorize?: false)
        |> Ash.create!()
    end
  end

  defp user_with(permissions, site_id \\ nil) do
    email = "#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      User
      |> Ash.Changeset.for_create(
        :register_with_password,
        %{email: email, password: @password, password_confirmation: @password},
        authorize?: false
      )
      |> then(fn cs -> (site_id && Ash.Changeset.set_tenant(cs, site_id)) || cs end)
      |> Ash.create()

    for permission <- List.wrap(permissions) do
      UserPermission
      |> Ash.Changeset.for_create(:assign, %{}, authorize?: false)
      |> Ash.Changeset.force_change_attribute(:user_id, user.id)
      |> Ash.Changeset.force_change_attribute(:permission_id, permission!(permission).id)
      |> Ash.create!(authorize?: false)
    end

    Ash.load!(user, [permissions: [:name]], authorize?: false)
  end

  defp code_error?({:error, error}), do: Exception.message(error) =~ CodeAccess.refusal()

  defp code_error?(_result), do: false

  # THE ACTOR HAS TO REACH THE CHANGESET, not just the call. Validations run when the changeset is
  # BUILT, so `save_section/5` hands the actor to the changeset — without it the write names nobody
  # and its Elixir is refused.
  describe "save_section/5 hands the actor to the changeset" do
    test "so a holder of the page area writes Elixir through the builder's own path", %{
      site: site
    } do
      page = create_page!(site_id: site.id)

      assert {:ok, saved} =
               save_section(
                 page,
                 site,
                 %{"events" => @handler, "infos" => [], "helpers" => []},
                 user_with("admin:dashboard:runtime:page", site.id)
               )

      assert [%{name: "save"}] = saved.events
    end

    test "and a master holding every name, through the same path", %{site: site} do
      page = create_page!(site_id: site.id)

      assert {:ok, saved} = save_section(page, site, %{"events" => @handler}, user_with("*"))
      assert [%{name: "save"}] = saved.events
    end

    test "and refuses one who may not write the page", %{site: site} do
      page = create_page!(site_id: site.id)

      assert {:error, _refused} =
               save_section(
                 page,
                 site,
                 %{"events" => @handler},
                 user_with("admin:dashboard:runtime:layout", site.id)
               )
    end
  end

  # A deployment that does not want author-written server code turns it off in ONE place.
  describe "the deployment switch" do
    setup do
      Application.put_env(:mishka_cms_core, :page_code, :off)
      :ok
    end

    # What the builder generates from its tree is not typed; its code drawer's Elixir is.
    test "off lets the builder's generated template through and refuses its Elixir", %{
      site: site
    } do
      actor = user_with("admin:dashboard:runtime:page", site.id)
      page = create_page!(site_id: site.id)

      assert {:ok, %{template: "<section>built</section>"}} =
               save_section(page, site, %{"template" => "<section>built</section>"}, actor)

      assert code_error?(save_section(page, site, %{"events" => @handler}, actor))
    end

    # The recovery screen's box: markup typed by hand, not generated from a tree.
    test "off refuses a template the builder was handed typed", %{site: site} do
      page = create_page!(site_id: site.id, template: "<div>stored</div>")
      actor = user_with("admin:dashboard:runtime:page", site.id)

      assert code_error?(
               save_section(page, site, %{"template" => "<div>typed</div>"}, actor, typed: true)
             )
    end
  end

  defp save_section(page, site, fields, actor, opts \\ []) do
    MishkaCmsBuilder.Helpers.save_section(
      MishkaCmsCore.Runtime.Page,
      &Ash.get(MishkaCmsCore.Runtime.Page, &1, &2),
      Map.merge(%{"id" => page.id, "site_id" => site.id}, fields),
      actor,
      opts
    )
  end

  defp helpers, do: [%{"name" => "shout", "args" => "text", "code" => "String.upcase(text)"}]
end
