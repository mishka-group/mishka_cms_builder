# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Runtime.StylesheetLoadOrderTest do
  @moduledoc """
  Which stylesheet wins, and the two places that have to agree about it.

  `priority` documents itself as *lower loads first, so a higher value wins on equal specificity*,
  and the `:for_compiler` read already sorted that way. Then both consumers re-sorted the rows on
  `-priority`: `TailwindCompiler.format_stylesheets/1`, which decides what the browser sees, and
  `MishkaCmsBuilder.Tokens.token_sheets/1`, which decides what Studio shows. Negating it emits the
  highest value FIRST, and CSS is last-wins — so the LOWEST priority sheet won.

  The two agreed with each other, which is exactly why it was invisible: Studio displayed the value
  the page really rendered. Both were the opposite of what an operator setting `priority: 90` asked
  for, and nothing said so.

  `Stylesheet.load_order/1` is now the single key both sort by, so they cannot drift apart again.

  `async: false` — global stylesheet rows are visible to every site.
  """
  use MishkaCmsCore.DataCase, async: false

  alias MishkaCmsBuilder.Tokens
  alias MishkaCmsCore.Runtime.Stylesheet

  defp sheet!(name, content, opts) do
    Stylesheet
    |> Ash.Changeset.for_create(
      :master_create,
      %{
        name: name,
        kind: Keyword.get(opts, :kind, :theme),
        content: content,
        site_id: nil,
        active: true,
        priority: Keyword.fetch!(opts, :priority)
      },
      authorize?: false
    )
    |> Ash.create!()
  end

  describe "Studio and the browser agree" do
    test "the token Studio reports is the one the higher-priority sheet declares" do
      run = System.unique_integer([:positive])
      key = "pri-#{run}"

      sheet!("pri-low-#{run}", ":root {\n  --#{key}: #111111;\n}\n", priority: 10)
      sheet!("pri-high-#{run}", ":root {\n  --#{key}: #de1135;\n}\n", priority: 90)

      token = Tokens.list(nil) |> Enum.find(&(&1.key == key))

      assert token, "both sheets were read, so the token must be listed"

      assert token.value == "#de1135",
             "priority 90 beats priority 10 — that is what the attribute promises"
    end

    # `put/4` writes into the sheet whose declaration WINS, so the value an operator edits is the
    # value they were shown. That falls out of the same ordering.
    test "writing a token edits the sheet whose declaration wins" do
      run = System.unique_integer([:positive])
      key = "priw-#{run}"

      low = sheet!("priw-low-#{run}", ":root {\n  --#{key}: #111111;\n}\n", priority: 10)
      high = sheet!("priw-high-#{run}", ":root {\n  --#{key}: #de1135;\n}\n", priority: 90)

      master = MishkaCmsCore.Test.Factory.create_user_with_permissions!(["*"])

      assert {:ok, _token} = Tokens.put(master, nil, "--" <> key, "#00ff00")

      reload = fn record ->
        Stylesheet
        |> Ash.get!(record.id, authorize?: false, action: :read_any)
        |> Map.fetch!(:content)
      end

      assert reload.(high) =~ "#00ff00"
      assert reload.(low) =~ "#111111", "the losing sheet is left alone"
    end
  end
end
