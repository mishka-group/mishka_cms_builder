# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Collection do
  @moduledoc """
  The list or map an attribute is holding, read out of a document and written back into one.

  ## Why this is not a text box

  `chelekom-filterable-gallery` keeps its whole content in two `list` attributes — the filter
  buttons and the pictures behind them — and thirty-nine attributes across the shipped kit are
  shaped the same way. The panel drew a one-line box for every one of them and wrote what was typed
  as a STRING, so a component that maps over its own attribute raised the moment anything was
  entered. The report reads "we cannot add any image and it's not clear how it works".

  So the panel needs a control that knows it is holding a collection, and that control needs to read
  the list, change one item, and write the whole thing back as one edit. That is this module.

  ## What counts as readable

  `MishkaCmsCore.Builder.Literal` decides, and it decides by walking the quoted form rather than
  evaluating it: a list of strings, a list of maps, a keyword list. Anything else — a binding, a
  function call, an interpolation — answers `:error`, and a caller holding `:error` must leave the
  attribute alone rather than overwrite what it could not read. An author who has written
  `media={@photos}` means it.

  ## And what is written back

  `inspect/1`, which is the exact shape the editor can read again. One `set_attr` per change, so one
  undo step per add, per removal and per edit.

  ## Lists inside items

  A tree's node holds its own `children`, a list of nodes like it. `within/3` applies a change to the
  list a PATH leads to — the item's index, then the field holding the next list, as deep as it goes —
  and puts every level around it back as it was. A map met on the way is edited as its pairs and
  written back a map.

  ## A write is read as what it replaces

  A box posts text, and the field it edits may hold a switch, a number or a list. Text written as it
  came turned a node's `children` into a string and the tree raised, so every setter reads the text
  as the kind of value already there: a switch from `"true"`, a number when it parses, and nothing at
  all into a list, a map, a tuple or an atom, which have editors of their own or are the component's
  own words.
  """

  alias MishkaCmsCore.Builder.Literal
  alias MishkaCmsCore.Runtime.Authoring.Tree.Node

  @doc """
  The collection an attribute holds on this node, or the declared default when it holds nothing.

  `:error` when the attribute is there and is not data — a binding rather than a list.
  """
  @spec read(Node.t() | term(), String.t(), term()) :: {:ok, list()} | :error
  def read(node, name, default \\ []) do
    case held(node, name, default) do
      {:ok, value} -> {:ok, listed(value)}
      :error -> :error
    end
  end

  @doc """
  The collection after `change`, as the source to write back: the list `read/3` gives is handed to
  `change`, and a MAP attribute is written back a map. Writing its pairs as they were edited put a
  list where `chelekom-flash` reads `Phoenix.Flash.get(@flash, :info)`.

  `:error` when the attribute is not data, as for `read/3`.
  """
  @spec update(Node.t() | term(), String.t(), term(), (list() -> list())) ::
          {:ok, String.t()} | :error
  def update(node, name, default, change) do
    case held(node, name, default) do
      {:ok, %{} = map} -> {:ok, map |> listed() |> change.() |> Map.new() |> write()}
      {:ok, value} -> {:ok, value |> listed() |> change.() |> write()}
      :error -> :error
    end
  end

  defp held(node, name, default) do
    case Node.attr(node, name) do
      nil -> {:ok, default}
      {:expr, source} -> Literal.value(source)
      {:string, ""} -> {:ok, default}
      {:string, source} -> Literal.value(source)
      _other -> :error
    end
  end

  @doc "The source text for a collection, ready to be written as an expression attribute."
  @spec write(list() | map()) :: String.t()
  def write(items) when is_list(items) or is_map(items),
    do: inspect(items, limit: :infinity, printable_limit: :infinity)

  @doc """
  One item changed, added or dropped, and the whole collection back.

  Out-of-range indexes are left alone rather than raising: the panel and the document can disagree
  for one render after an undo, and a stale click must not take the editor down.
  """
  @spec put(list(), non_neg_integer(), term()) :: list()
  def put(items, index, value) when is_list(items) and index >= 0 do
    with {:ok, existing} <- Enum.fetch(items, index),
         false <- is_nil(existing),
         {:ok, fitted} <- fit(existing, value) do
      List.replace_at(items, index, fitted)
    else
      _absent_or_unfit -> items
    end
  end

  @doc """
  One field of one item changed. The key is the field's name, as an atom or as the text the browser
  sent: a name the item has no field for leaves the collection as it was, and no atom is made of it.
  """
  @spec put_in_item(list(), non_neg_integer(), atom() | String.t(), term()) :: list()
  def put_in_item(items, index, key, value) when is_list(items) do
    with %{} = item <- at(items, index),
         field when not is_nil(field) <- field_of(item, key),
         {:ok, fitted} <- fit(Map.fetch!(item, field), value) do
      List.replace_at(items, index, Map.put(item, field, fitted))
    else
      _no_such_field -> items
    end
  end

  @doc """
  One place of a tuple item changed, counted from 0: `chelekom-headless-segmented-control` takes
  `{label, value, disabled}` beside its plain words, and each place is edited as what it holds.
  """
  @spec put_element(list(), non_neg_integer(), non_neg_integer(), term()) :: list()
  def put_element(items, index, position, value) when is_list(items) and is_integer(position) do
    with item when is_tuple(item) <- at(items, index),
         true <- position >= 0 and position < tuple_size(item),
         {:ok, fitted} <- fit(elem(item, position), value) do
      List.replace_at(items, index, put_elem(item, position, fitted))
    else
      _not_a_place -> items
    end
  end

  @doc """
  `fun` applied to the list `path` leads to, and the whole collection back.

  A path alternates an item's index and the field of that item holding the next list — `[1,
  "children"]` is the second node's children — and the field may be a tuple's place, `"__1"`. A map
  on the way is handed to `fun` as its pairs and written back a map. A path that no longer leads to a
  list or a map, which a stale click after an undo can send, leaves the collection as it was.
  """
  @spec within(list(), [non_neg_integer() | String.t()], (list() -> list())) :: list()
  def within(items, [], fun) when is_list(items), do: fun.(items)

  def within(items, [index, key | rest], fun) when is_list(items) and is_integer(index) do
    with item when not is_nil(item) <- at(items, index),
         {:ok, changed} <- descend(item, key, rest, fun) do
      List.replace_at(items, index, changed)
    else
      _lost -> items
    end
  end

  def within(items, _path, _fun), do: items

  @doc """
  An empty item added to the end of the list `path` leads to, shaped like the ones beside it.

  An empty nested list has nothing beside it to read, so the same field's list elsewhere in the
  collection answers — a node's first child takes the shape of another node's children — and failing
  that the list holding it, because a tree's children are shaped like their parent. `fallback` is
  the answer for the top list when it is empty, as for `blank/2`.
  """
  @spec add_blank(list(), [non_neg_integer() | String.t()], term()) :: list()
  def add_blank(items, path, fallback \\ "") do
    within(items, path, &add(&1, blank(&1, sample_for(items, path, fallback))))
  end

  defp sample_for(_items, [], fallback), do: fallback

  defp sample_for(items, path, fallback) do
    holder = Enum.drop(path, -2)

    case items |> lists_under(List.last(path)) |> Enum.find(&(&1 != [])) do
      nil -> items |> fetch(holder) |> listed() |> blank(fallback)
      sibling -> blank(sibling, fallback)
    end
  end

  # Every list held under a field named `key`, anywhere in the collection.
  defp lists_under(value, key) when is_list(value),
    do: Enum.flat_map(value, &lists_under(&1, key))

  defp lists_under(%{} = value, key) do
    own = for {field, held} <- value, field_name(field) == key, is_list(held), do: held
    own ++ Enum.flat_map(Map.values(value), &lists_under(&1, key))
  end

  defp lists_under(_value, _key), do: []

  defp fetch(value, []), do: value

  defp fetch(items, [index, key | rest]) when is_list(items) and is_integer(index) do
    case items |> at(index) |> part(key) do
      {:ok, inner} -> inner |> listed() |> fetch(rest)
      :error -> nil
    end
  end

  defp fetch(_value, _path), do: nil

  defp descend(item, key, rest, fun) do
    with {:ok, inner} <- part(item, key),
         {:ok, changed} <- container(inner, rest, fun) do
      replace_part(item, key, changed)
    end
  end

  defp container(value, rest, fun) when is_list(value), do: {:ok, within(value, rest, fun)}

  defp container(%{} = value, rest, fun),
    do: {:ok, value |> Enum.to_list() |> within(rest, fun) |> Map.new()}

  defp container(_value, _rest, _fun), do: :error

  # The value one field of an item holds: a map's field, found by its name, or a tuple's place.
  defp part(%{} = item, key) do
    case field_of(item, key) do
      nil -> :error
      field -> {:ok, Map.fetch!(item, field)}
    end
  end

  defp part(item, key) when is_tuple(item) do
    case place(key) do
      position when is_integer(position) and position < tuple_size(item) ->
        {:ok, elem(item, position)}

      _no_place ->
        :error
    end
  end

  defp part(_item, _key), do: :error

  defp replace_part(%{} = item, key, value), do: {:ok, Map.put(item, field_of(item, key), value)}
  defp replace_part(item, key, value), do: {:ok, put_elem(item, place(key), value)}

  @doc """
  The place a tuple field names: `"__0"`, `"__1"`… and, for a pair, `"__key"` and `"__value"`.
  `nil` for anything else.
  """
  @spec place(term()) :: non_neg_integer() | nil
  def place("__key"), do: 0
  def place("__value"), do: 1

  def place("__" <> digits) do
    case Integer.parse(digits) do
      {position, ""} when position >= 0 -> position
      _other -> nil
    end
  end

  def place(_key), do: nil

  defp field_of(item, key) when is_atom(key), do: (Map.has_key?(item, key) && key) || nil
  defp field_of(item, key), do: Enum.find(Map.keys(item), &(field_name(&1) == key))

  defp at(items, index) when is_integer(index) and index >= 0 do
    case Enum.fetch(items, index) do
      {:ok, item} -> item
      :error -> nil
    end
  end

  defp at(_items, _index), do: nil

  # WHAT THE BOX SENT, AS WHAT THE FIELD HOLDS. Text replaces text; a switch takes `"true"` and
  # `"false"`; a number takes text that parses as one. A list, a map, a tuple or an atom is never
  # replaced by text: they are edited by editors of their own, or are the component's own words.
  # A value that is not text is the editor's own and goes in as it is.
  defp fit(_existing, value) when not is_binary(value), do: {:ok, value}
  defp fit(existing, value) when is_binary(existing) or is_nil(existing), do: {:ok, value}
  defp fit(existing, value) when is_boolean(existing), do: {:ok, value in ["true", "on"]}

  defp fit(existing, value) when is_integer(existing) do
    case Integer.parse(String.trim(value)) do
      {number, ""} -> {:ok, number}
      _not_a_number -> :error
    end
  end

  defp fit(existing, value) when is_float(existing) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> {:ok, number}
      _not_a_number -> :error
    end
  end

  defp fit(_existing, _value), do: :error

  defp field_name(key) when is_atom(key), do: Atom.to_string(key)
  defp field_name(key) when is_binary(key), do: key
  defp field_name(_key), do: nil

  @spec add(list(), term()) :: list()
  def add(items, value) when is_list(items), do: items ++ [value]

  @spec remove(list(), non_neg_integer()) :: list()
  def remove(items, index) when is_list(items) and index >= 0, do: List.delete_at(items, index)

  @doc """
  What an empty row of this collection looks like, read off the ones already there.

  A list of maps gets a map with the same keys blank, so the new card carries the same fields as its
  neighbours, and a list of tuples a tuple blank in each place; a list of anything else gets an
  empty string. BLANK IS THE EMPTY VALUE OF WHAT THE FIELD HOLDS: a list stays a list and a map a map,
  because a tree iterates its node's `children` and `children: ""` raised on the canvas; a switch is
  off. An empty list has nothing to read, and the caller's own sample is the answer —
  `MishkaCmsBuilder.Starter` has one for the shapes it knows.
  """
  @spec blank(list(), term()) :: term()
  def blank(items, fallback \\ "") do
    cond do
      sample = Enum.find(items, &is_map/1) ->
        Map.new(sample, fn {key, value} -> {key, empty(value)} end)

      sample = Enum.find(items, &is_tuple/1) ->
        empty(sample)

      true ->
        fallback
    end
  end

  defp empty(value) when is_list(value), do: []
  defp empty(%{} = _value), do: %{}
  defp empty(value) when is_boolean(value), do: false

  defp empty(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.map(&empty/1) |> List.to_tuple()

  defp empty(_value), do: ""

  @doc """
  Whether an item is one side of a map or a keyword list rather than a value on its own.

  A `map` attribute is read out as its pairs — `chelekom-flash` holds `%{"info" => "…"}` and
  `chelekom-pagination` a map of query parameters — and a pair is edited as a pair, one field for
  each side.
  """
  @spec pair?(term()) :: boolean()
  def pair?({_key, _value}), do: true
  def pair?(_item), do: false

  @doc "One side of a pair changed, the other left as it was."
  @spec put_side(list(), non_neg_integer(), :key | :value, term()) :: list()
  def put_side(items, index, side, value) do
    case at(items, index) do
      {_key, _existing} -> put_element(items, index, (side == :key && 0) || 1, value)
      _not_a_pair -> items
    end
  end

  defp listed(value) when is_list(value), do: value
  defp listed(%{} = value), do: Enum.to_list(value)
  defp listed(_other), do: []
end
