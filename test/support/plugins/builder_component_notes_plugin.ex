# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Test.Plugins.BuilderComponentNotesPlugin do
  @moduledoc """
  An extension that has something to tell the author about its own block, as
  `builder:component:notes` allows: `acme-product` pointed at the product `gone` gets a warning
  naming it, every other product and component gets nothing. Each ask is reported to the process
  registered as `waiter/0`, when there is one, so a test can count them.
  """
  use MishkaInstaller.Event.Hook, event: "builder:component:notes"

  @doc "The name a test registers itself under to hear each ask."
  @spec waiter() :: atom()
  def waiter, do: :builder_component_notes_waiter

  @impl true
  def call(%{component: component, attrs: attrs} = payload) do
    case Process.whereis(waiter()) do
      nil -> :ok
      pid -> send(pid, {__MODULE__, component, attrs, payload.site_id})
    end

    {:reply, %{payload | notes: payload.notes ++ notes(component, attrs)}}
  end

  def call(payload), do: {:reply, payload}

  defp notes("acme-product", %{"product" => "gone"}) do
    [
      %{
        severity: :warning,
        message: "The product gone was archived.",
        detail: "Visitors see nothing in this block."
      }
    ]
  end

  defp notes(_component, _attrs), do: []
end
