# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Test.Plugins.BuilderExamplesPlugin do
  @moduledoc """
  An extension that ships an example of its own for a component, as `builder:examples` allows: it
  puts one in front of whatever the kit offers for `promo-card`, and leaves every other component's
  list alone.
  """
  use MishkaInstaller.Event.Hook, event: "builder:examples"

  @heading "From the plugin"

  @doc "The heading the plugin's example shows."
  @spec heading() :: String.t()
  def heading, do: @heading

  @impl true
  def call(%{entry: "promo-card", examples: examples} = payload),
    do: {:reply, %{payload | examples: [example() | examples]}}

  def call(payload), do: {:reply, payload}

  defp example do
    %{
      id: "from-the-plugin-0",
      title: "From the plugin",
      description: "An example an extension ships",
      source: ~s(<section id="from-the-plugin"><h3>#{@heading}</h3></section>),
      composed?: true,
      base?: false,
      section: nil,
      requires: %{}
    }
  end
end
