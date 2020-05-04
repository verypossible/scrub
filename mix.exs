defmodule Scrub.MixProject do
  use Mix.Project

  def project do
    [
      app: :scrub,
      version: "0.1.2",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:db_connection, "~> 2.2"},
      {:ex_doc, "~> 0.18", only: [:dev, :test], runtime: false}
    ]
  end
end
