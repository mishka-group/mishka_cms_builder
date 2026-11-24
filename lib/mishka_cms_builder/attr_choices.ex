# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.AttrChoices do
  @moduledoc """
  The choices of an attribute whose kit names a source for them (`opts.choices`), read for the
  Inspector: the products of the site a block shows, the categories of a blog.

  The choices come from `MishkaCmsCore.Builder.Events.attr_choices/1`, the `builder:attr:choices`
  event, asked with the source, the component, the attribute and the site. Only the editor asks, so
  a published page never pays for it.

  ## One ask for the same source

  The Inspector draws again on every keystroke, and a plugin reads something to answer. So an answer
  is kept in the asking process for a few seconds under what was asked (the source, the component,
  the attribute and the site), as `MishkaCmsBuilder.ComponentNotes` keeps its notes: the renders of a
  burst of typing share one ask, and a product published a moment ago is offered a few seconds later.
  """

  alias MishkaCmsCore.Builder.Events
  alias MishkaCmsCore.Runtime.Authoring.Inspector

  @memo {__MODULE__, :asked}
  @fresh_ms 5_000

  @doc """
  `attr` ready for its control: with the choices its source offers on the site of `scope` (`:site_id`
  and `:site_name`) as its values and their labels (`Inspector.with_choices/2`), a text box when the
  source offers nothing, and as it is when its kit names no source. `component` is the component's
  name.
  """
  @spec resolved(map(), String.t() | nil, map()) :: map()
  def resolved(attr, component, scope) do
    case Inspector.choices_source(attr) do
      nil ->
        attr

      source ->
        question = %{
          source: source,
          component: component,
          attr: Inspector.name(attr),
          site_id: scope[:site_id],
          site_name: scope[:site_name]
        }

        question |> asked() |> offered(attr)
    end
  end

  @doc "Drops the answers this process kept, so the next ask goes to the extensions again."
  @spec forget() :: :ok
  def forget do
    Process.delete(@memo)
    :ok
  end

  defp offered([], attr) do
    opts = attr |> Inspector.opts() |> Map.put("editor", "text") |> Map.delete("values")
    attr |> Map.new(fn {key, value} -> {to_string(key), value} end) |> Map.put("opts", opts)
  end

  defp offered(choices, attr), do: Inspector.with_choices(attr, choices)

  defp asked(question) do
    now = System.monotonic_time(:millisecond)
    kept = Process.get(@memo, %{})

    case kept do
      %{^question => {choices, at}} when now - at < @fresh_ms ->
        choices

      _stale_or_new ->
        choices = Events.attr_choices(question)

        fresh =
          for {key, {_choices, at} = answer} <- kept,
              now - at < @fresh_ms,
              into: %{},
              do: {key, answer}

        Process.put(@memo, Map.put(fresh, question, {choices, now}))
        choices
    end
  end
end
