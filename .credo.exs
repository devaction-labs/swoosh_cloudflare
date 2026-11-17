%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: true,
      checks: %{
        disabled: [
          # Cloudflare error codes (10001, 10202, ...) are identifiers, not quantities.
          {Credo.Check.Readability.LargeNumbers, []}
        ]
      }
    }
  ]
}
