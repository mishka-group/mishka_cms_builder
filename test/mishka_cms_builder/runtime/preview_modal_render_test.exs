# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Runtime.PreviewModalRenderTest do
  @moduledoc """
  Renders the runtime preview modal's drafts strip to validate the Visual Editor link: it opens the
  editor on the draft the author selected, not on whichever is newest.
  """
  use ExUnit.Case, async: true
  @moduletag :unit

  import Phoenix.LiveViewTest
  alias MishkaCmsCoreWeb.Live.Admin.Components.RuntimePreviewModal
  alias MishkaCmsCoreWeb.Live.Admin.Dashboard.Runtime.PreviewHelpers
  alias MishkaCmsCore.Runtime.{ErrorPage, Page, PageDraft}

  # Merged onto the real shape rather than a copy of it: a copy goes stale the moment a key is
  # added to the modal, and fails as a KeyError from the template instead of a behaviour.
  defp state(overrides) do
    PreviewHelpers.empty()
    |> Map.put(:resource, ErrorPage)
    |> Map.put(:active_tab, "preview")
    |> Map.merge(Map.new(overrides))
  end

  # THE DRAFTS STRIP, which is the modal's answer to "which of these am I looking at". The link to
  # the editor is about the SELECTED badge, which is what these pin.
  describe "the drafts strip" do
    defp draft(id, label, day) do
      struct(PageDraft,
        id: id,
        label: label,
        updated_at: DateTime.new!(Date.new!(2026, 8, day), ~T[11:18:00], "Etc/UTC")
      )
    end

    defp strip(overrides) do
      drafts = [
        draft("d-1", "Newest", 26),
        draft("d-2", "Middle", 25),
        draft("d-3", "Oldest", 24)
      ]

      state(
        Map.merge(
          %{
            resource: Page,
            active_tab: "overview",
            record: struct(Page, id: "rec-page", name: "Forms", path: "/forms"),
            drafts_enabled?: true,
            writable?: true,
            drafts: drafts,
            drafts_total: 3,
            draft: List.first(drafts)
          },
          Map.new(overrides)
        )
      )
    end

    defp render_strip(overrides),
      do: render_component(&RuntimePreviewModal.modal/1, preview: strip(overrides))

    # LEAVING FOR THE BUILDER USED TO FORGET THE CHOICE. The editor read the drafts table for itself
    # and offered whichever was newest, so picking the second badge and clicking through arrived at
    # an offer to carry on with the first.
    test "the Visual Editor link carries the selected draft" do
      html =
        render_strip(%{
          visual_editor_url: "/admin/dashboard/runtime/builder/page/rec-page",
          draft: draft("d-2", "Middle", 25)
        })

      assert html =~ "/admin/dashboard/runtime/builder/page/rec-page?draft_id=d-2"
    end

    test "and joins it onto a site_id that is already on the URL" do
      html =
        render_strip(%{
          visual_editor_url: "/admin/dashboard/runtime/builder/page/rec-page?site_id=site-9",
          draft: draft("d-2", "Middle", 25)
        })

      assert html =~ "builder/page/rec-page?site_id=site-9&amp;draft_id=d-2"
    end

    test "with nothing selected the link is left exactly as it was" do
      html =
        render_strip(%{
          visual_editor_url: "/admin/dashboard/runtime/builder/page/rec-page",
          draft: nil
        })

      assert html =~ "/admin/dashboard/runtime/builder/page/rec-page"
      refute html =~ "draft_id="
    end
  end
end
