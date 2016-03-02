defmodule Lakeland.AppTest do
  use ExUnit.Case

  test "lakeland app shoud start correctly" do
    assert Application.started_applications |> List.keymember?(:lakeland, 0)
  end

end
