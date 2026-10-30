# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Activity.ActivityAreasTest do
  @moduledoc """
  The editor's entries in the Activity log are shown by their document's area, like any other entry
  (core's `Activity.ActivityAreasTest`): the activity area alone shows no job and no editor change,
  and a holder of the media and activity areas sees no editor change or draft of a page that a full
  dashboard admin sees.
  """
  use MishkaCmsCore.DataCase, async: false

  alias MishkaCmsCore.Activity.{Helpers, Query}

  setup do
    site = create_site!()
    create_media!(site_id: site.id)
    create_page!(site_id: site.id)
    {:ok, site: site}
  end

  defp holder(names, site), do: create_user_with_permissions!(names, site_id: site.id)

  describe "every kind of entry" do
    @repo Application.compile_env!(:mishka_cms_core, :repo)

    defp job!(resource, site) do
      {:ok, _} =
        Ecto.Adapters.SQL.query(
          @repo,
          "INSERT INTO oban_jobs (state, queue, worker, args, completed_at, inserted_at, scheduled_at) " <>
            "VALUES ('completed', 'modules', $1, $2, now(), now(), now())",
          [
            "Elixir.MishkaCmsCore.Runtime.Workers.RuntimeCompilerWorker",
            %{"resource" => resource, "site_id" => site.id}
          ]
        )
    end

    defp editor_change!(site, page) do
      MishkaCmsBuilder.HistoryEvent
      |> Ash.Changeset.for_create(
        :create,
        %{
          id: Ecto.UUID.generate(),
          source_type: :page,
          source_id: page.id,
          site_id: site.id,
          label: "Set gap (base)",
          target: "<nav>",
          kind: :style,
          op: :set_style
        },
        tenant: site.id,
        authorize?: false
      )
      |> Ash.create!(authorize?: false)
    end

    defp page_draft!(site) do
      MishkaCmsCore.Runtime.PageDraft
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: "areas-draft",
          title: "areas-draft",
          path: "/areas-draft",
          template: "<h1>x</h1>"
        },
        tenant: site.id
      )
      |> Ash.create!(authorize?: false)
    end

    defp entries(actor, site, kind) do
      Query.page(%{
        site_id: site.id,
        kind: kind,
        resources: Helpers.resources_for(actor),
        limit: 100,
        offset: 0
      })
    end

    test "the activity area alone shows no job and no editor change", %{site: site} do
      job!("MishkaCmsCore.Runtime.Media", site)
      editor_change!(site, create_page!(site_id: site.id))

      reader = holder(["admin:dashboard:runtime:activity"], site)

      assert entries(reader, site, nil) == []
    end

    test "an editor change and a draft follow their document's area", %{site: site} do
      page = create_page!(site_id: site.id)
      editor_change!(site, page)
      page_draft!(site)

      reader = holder(["admin:dashboard:runtime:activity", "admin:dashboard:runtime:media"], site)
      full = holder(["admin:dashboard:*"], site)
      badges = fn actor -> actor |> entries(site, "content") |> Enum.map(& &1.resource_label) end

      assert "Page Draft" in badges.(full)
      assert Enum.any?(badges.(full), &(&1 =~ "Editor"))
      refute "Page Draft" in badges.(reader)
      refute Enum.any?(badges.(reader), &(&1 =~ "Editor"))
    end
  end
end
