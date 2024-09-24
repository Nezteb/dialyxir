defmodule Dialyxir.FormatterTest do
  use ExUnit.Case

  import ExUnit.CaptureIO, only: [capture_io: 1]

  alias Dialyxir.Formatter
  alias Dialyxir.Formatter.Dialyxir, as: DialyxirFormatter
  alias Dialyxir.Formatter.Dialyzer, as: DialyzerFormatter
  alias Dialyxir.Formatter.Github, as: GithubFormatter
  alias Dialyxir.Formatter.Short, as: ShortFormatter
  alias Dialyxir.Formatter.IgnoreFileStrict, as: IgnoreFileStrictFormatter
  alias Dialyxir.Project

  defp in_project(app, f) when is_atom(app) do
    Mix.Project.in_project(app, "test/fixtures/#{Atom.to_string(app)}", fn _ -> f.() end)
  end

  describe "formats dialyzer warning" do
    if System.otp_release() >= "24" do
      for {formatter, message} <- %{
            Formatter.Dialyxir =>
              "lib/file/warning_type/line.ex:19:4:no_return\nFunction format_long/1 has no local return.",
            Formatter.Dialyzer =>
              "lib/file/warning_type/line.ex:19:4: Function format_long/1 has no local return",
            Formatter.Github =>
              "::warning file=lib/file/warning_type/line.ex,line=19,col=4,title=no_return::Function format_long/1 has no local return.",
            Formatter.IgnoreFileStrict =>
              ~s|{"lib/file/warning_type/line.ex", "Function format_long/1 has no local return."},|,
            Formatter.IgnoreFile => ~s|{"lib/file/warning_type/line.ex", :no_return},|,
            # TODO: Remove if once only Elixir ~> 1.15 is supported
            Formatter.Raw =>
              if Version.match?(System.version(), "<= 1.15.0") do
                ~s|{:warn_return_no_exit, {'lib/file/warning_type/line.ex', {19, 4}}, {:no_return, [:only_normal, :format_long, 1]}}|
              else
                ~s|{:warn_return_no_exit, {~c"lib/file/warning_type/line.ex", {19, 4}}, {:no_return, [:only_normal, :format_long, 1]}}|
              end,
            Formatter.Short =>
              "lib/file/warning_type/line.ex:19:4:no_return Function format_long/1 has no local return."
          } do
        test "file location including column for #{formatter} formatter" do
          assert {:warn, [message], _unused_filters} =
                   Formatter.format_and_filter(
                     [
                       {:warn_return_no_exit, {~c"lib/file/warning_type/line.ex", {19, 4}},
                        {:no_return, [:only_normal, :format_long, 1]}}
                     ],
                     Project,
                     [],
                     [unquote(formatter)]
                   )

          assert message =~ unquote(message)
        end
      end
    end
  end

  describe "exs ignore" do
    test "evaluates an ignore file and ignores warnings matching the pattern" do
      warnings = [
        {:warn_return_no_exit, {~c"lib/short_description.ex", 17},
         {:no_return, [:only_normal, :format_long, 1]}},
        {:warn_return_no_exit, {~c"lib/file/warning_type.ex", 18},
         {:no_return, [:only_normal, :format_long, 1]}},
        {:warn_return_no_exit, {~c"lib/file/warning_type/line.ex", 19},
         {:no_return, [:only_normal, :format_long, 1]}}
      ]

      in_project(:ignore, fn ->
        {:error, remaining, _unused_filters_present} =
          Formatter.format_and_filter(warnings, Project, [], [ShortFormatter])

        assert remaining == []
      end)
    end

    test "evaluates an ignore file of the form {file, short_description} and ignores warnings matching the pattern" do
      warnings = [
        {:warn_return_no_exit, {~c"lib/poorly_written_code.ex", 10},
         {:no_return, [:only_normal, :do_a_thing, 1]}},
        {:warn_return_no_exit, {~c"lib/poorly_written_code.ex", 20},
         {:no_return, [:only_normal, :do_something_else, 2]}},
        {:warn_return_no_exit, {~c"lib/poorly_written_code.ex", 30},
         {:no_return, [:only_normal, :do_many_things, 3]}}
      ]

      in_project(:ignore_strict, fn ->
        {:ok, remaining, :no_unused_filters} =
          Formatter.format_and_filter(warnings, Project, [], [IgnoreFileStrictFormatter])

        assert remaining == []
      end)
    end

    test "does not filter lines not matching the pattern" do
      warning =
        {:warn_return_no_exit, {~c"a/different_file.ex", 17},
         {:no_return, [:only_normal, :format_long, 1]}}

      in_project(:ignore, fn ->
        {:error, [remaining], _} =
          Formatter.format_and_filter([warning], Project, [], [ShortFormatter])

        assert remaining =~ ~r/different_file.* no local return/
      end)
    end

    test "can filter by regex" do
      warning =
        {:warn_return_no_exit, {~c"a/regex_file.ex", 17},
         {:no_return, [:only_normal, :format_long, 1]}}

      in_project(:ignore, fn ->
        {:error, remaining, _unused_filters_present} =
          Formatter.format_and_filter([warning], Project, [], [ShortFormatter])

        assert remaining == []
      end)
    end

    test "lists unnecessary skips as warnings if ignoring exit status" do
      warning =
        {:warn_return_no_exit, {~c"a/regex_file.ex", 17},
         {:no_return, [:only_normal, :format_long, 1]}}

      filter_args = [{:ignore_exit_status, true}]

      in_project(:ignore, fn ->
        assert {:warn, [], {:unused_filters_present, warning}} =
                 Formatter.format_and_filter([warning], Project, filter_args, [:dialyxir])

        assert warning =~ "Unused filters:"
      end)
    end

    test "error on unnecessary skips without ignore_exit_status" do
      warning =
        {:warn_return_no_exit, {~c"a/regex_file.ex", 17},
         {:no_return, [:only_normal, :format_long, 1]}}

      filter_args = [{:ignore_exit_status, false}]

      in_project(:ignore, fn ->
        {:error, [], {:unused_filters_present, error}} =
          Formatter.format_and_filter([warning], Project, filter_args, [:dialyxir])

        assert error =~ "Unused filters:"
      end)
    end

    test "overwrite ':list_unused_filters_present'" do
      warning =
        {:warn_return_no_exit, {~c"a/regex_file.ex", 17},
         {:no_return, [:only_normal, :format_long, 1]}}

      filter_args = [{:list_unused_filters, false}]

      in_project(:ignore, fn ->
        assert {:warn, [], {:unused_filters_present, warning}} =
                 Formatter.format_and_filter([warning], Project, filter_args, [:dialyxir])

        refute warning =~ "Unused filters:"
      end)
    end
  end

  describe "simple string ignore" do
    test "evaluates an ignore file and ignores warnings matching the pattern" do
      warning =
        {:warn_matching, {~c"a/file.ex", 17}, {:pattern_match, [~c"pattern 'ok'", ~c"'error'"]}}

      in_project(:ignore_string, fn ->
        assert Formatter.format_and_filter([warning], Project, [], [:dialyzer]) ==
                 {:ok, [], :no_unused_filters}
      end)
    end
  end

  describe "multiple formatters" do
    test "short and github" do
      warning =
        {:warn_return_no_exit, {~c"a/different_file.ex", 17},
         {:no_return, [:only_normal, :format_long, 1]}}

      in_project(:ignore, fn ->
        {:error, [short_formatted, github_formatted], _} =
          Formatter.format_and_filter([warning], Project, [], [ShortFormatter, GithubFormatter])

        assert short_formatted =~ ~r/different_file.* no local return/
        assert github_formatted =~ ~r/^::warning file=a\/different_file\.ex.* no local return/
      end)
    end
  end

  test "listing unused filter behaves the same for different formats" do
    warnings = [
      {:warn_return_no_exit, {~c"a/regex_file.ex", 17},
       {:no_return, [:only_normal, :format_long, 1]}},
      {:warn_return_no_exit, {~c"a/another-file.ex", 18}, {:unknown_type, {:M, :F, :A}}}
    ]

    expected_warning = "a/another-file.ex:18"

    expected_unused_filter = ~s(Unused filters:
{"lib/short_description.ex:17:no_return Function format_long/1 has no local return."}
{"lib/file/warning_type.ex", :no_return, 18}
{"lib/file/warning_type/line.ex", :no_return, 19})

    filter_args = [{:list_unused_filters, true}]

    for format <- [ShortFormatter, DialyxirFormatter, DialyzerFormatter] do
      in_project(:ignore, fn ->
        capture_io(fn ->
          result = Formatter.format_and_filter(warnings, Project, filter_args, [format])

          assert {:error, [warning], {:unused_filters_present, unused}} = result
          assert warning =~ expected_warning
          assert unused == expected_unused_filter
          # A warning for regex_file.ex was explicitly put into format_and_filter.
          refute unused =~ "regex_file.ex"
        end)
      end)
    end
  end
end
