# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc """
  The builder's OTP application. It supervises the processes the visual editor keeps (the open
  sessions, their history, the rendered palette-card previews and the presence of the people in a
  session) and every mishka_installer plugin the package ships (`plugins/0`): the sidebar page, the
  editor's address, the snippet installer, the activity source, the settings and the history release
  of a deleted draft. A plugin registers on the event it listens on once it is supervised here.

  None of the processes needs the repo at init (each is an ETS table or Presence), so the application
  can start before the host's repo. `MishkaCmsBuilder.Presence` needs `MishkaCmsCore.PubSub`, which
  `:mishka_cms_core` starts first.
  """

  use Application

  @children [
    MishkaCmsBuilder.States.EditorSessionState,
    # After the session table: its sweep reads it.
    MishkaCmsBuilder.States.EditorHistoryState,
    MishkaCmsBuilder.States.CardPreviewState,
    MishkaCmsBuilder.Presence
  ]

  # `CardPreviewInvalidator` redraws the palette's card previews when a site's components recompile
  # (`runtime:after_module_compile`); `SidebarMenu` contributes the editor's admin pages
  # (`sidebar:menus`); `EditorUrl` answers `runtime:document:editor_url` so the dashboards offer an
  # "open in the editor" button; `ProvisionSnippet` installs an extension's snippet
  # (`runtime:provision:snippets`); `Activity.EditorHistory` merges the editor's history into the
  # activity log (`activity:sources`); `Settings` registers the `cms_builder.` keys and the mention
  # notification (`settings:register`); the six `ReleaseDraftHistory` modules release a deleted
  # draft's history on the draft's destroy events.
  @plugins [
    MishkaCmsBuilder.Plugins.CardPreviewInvalidator,
    MishkaCmsBuilderWeb.SidebarMenu,
    MishkaCmsBuilder.Plugins.EditorUrl,
    MishkaCmsBuilder.Plugins.ProvisionSnippet,
    MishkaCmsBuilder.Activity.EditorHistory,
    MishkaCmsBuilder.Plugins.Settings,
    MishkaCmsBuilder.Plugins.ReleaseDraftHistory.PageDraftDestroy,
    MishkaCmsBuilder.Plugins.ReleaseDraftHistory.PageDraftMasterDestroy,
    MishkaCmsBuilder.Plugins.ReleaseDraftHistory.LayoutDraftDestroy,
    MishkaCmsBuilder.Plugins.ReleaseDraftHistory.LayoutDraftMasterDestroy,
    MishkaCmsBuilder.Plugins.ReleaseDraftHistory.ErrorPageDraftDestroy,
    MishkaCmsBuilder.Plugins.ReleaseDraftHistory.ErrorPageDraftMasterDestroy
  ]

  @doc """
  Every mishka_installer plugin this package ships, all of which `start/2` supervises. A plugin left
  out of it never registers, so the event it listens on never reaches it.
  """
  @spec plugins() :: [module()]
  def plugins, do: @plugins

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: MishkaCmsBuilder.Supervisor]
    Supervisor.start_link(@children ++ @plugins, opts)
  end
end
