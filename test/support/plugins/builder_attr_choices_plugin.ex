# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Test.Plugins.BuilderAttrChoicesPlugin do
  @moduledoc """
  An extension that knows where an attribute's choices come from, as `builder:attr:choices` allows:
  the source `acme:products` offers two products of the site being edited, by name. Every other
  source gets nothing.
  """
  use MishkaInstaller.Event.Hook, event: "builder:attr:choices"

  @impl true
  def call(%{source: "acme:products", site_id: site_id} = payload) when is_binary(site_id) do
    choices = [
      %{value: "photo-pack", label: "Photo pack"},
      %{value: "icon-set", label: "Icon set"}
    ]

    {:reply, %{payload | choices: payload.choices ++ choices}}
  end

  def call(payload), do: {:reply, payload}
end
