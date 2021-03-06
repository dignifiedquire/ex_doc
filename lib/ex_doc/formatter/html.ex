defmodule ExDoc.Formatter.HTML do
  @moduledoc false

  alias ExDoc.Formatter.HTML.Templates
  alias ExDoc.Formatter.HTML.Autolink

  @main "extra-api-reference"

  @doc """
  Generate HTML documentation for the given modules
  """
  @spec run(list, %ExDoc.Config{}) :: String.t
  def run(module_nodes, config) when is_map(config) do
    config = normalize_config(config)
    output = Path.expand(config.output)
    File.rm_rf! output
    :ok = File.mkdir_p output

    generate_assets(output, config)

    all = Autolink.all(module_nodes)
    modules    = filter_list(:modules, all)
    exceptions = filter_list(:exceptions, all)
    protocols  = filter_list(:protocols, all)

    if config.logo do
      config = process_logo_metadata(config)
    end

    generate_api_reference(modules, exceptions, protocols, output, config)
    extras = generate_extras(output, module_nodes, modules, exceptions, protocols, config)

    generate_index(output, config)
    generate_not_found(modules, exceptions, protocols, output, config)
    generate_sidebar_items(modules, exceptions, protocols, extras, output)

    generate_list(modules, modules, exceptions, protocols, output, config)
    generate_list(exceptions, modules, exceptions, protocols, output, config)
    generate_list(protocols, modules, exceptions, protocols, output, config)

    Path.join(config.output, "index.html")
  end

  defp normalize_config(%{main: "index"}) do
    raise ArgumentError, message: "\"main\" cannot be set to \"index\", otherwise it will recursively link to itself"
  end
  defp normalize_config(%{main: main} = config) do
    %{config | main: main || @main}
  end

  defp generate_index(output, config) do
    generate_redirect(output, "index.html", config, "#{config.main}.html")
  end

  defp generate_api_reference(modules, exceptions, protocols, output, config) do
    content = Templates.api_reference_template(config, modules, exceptions, protocols)
    File.write!("#{output}/extra-api-reference.html", content)
  end

  defp generate_not_found(modules, exceptions, protocols, output, config) do
    content = Templates.not_found_template(config, modules, exceptions, protocols)
    File.write!("#{output}/404.html", content)
  end

  defp generate_sidebar_items(modules, exceptions, protocols, extras, output) do
    nodes = %{modules: modules, protocols: protocols,
              exceptions: exceptions, extras: extras}
    content = Templates.create_sidebar_items(nodes)
    File.write!("#{output}/dist/sidebar_items.js", content)
  end

  defp assets do
    [{templates_path("dist/*.{css,js}"), "dist"},
     {templates_path("fonts/*.{eot,svg,ttf,woff,woff2}"), "fonts"}]
  end

  defp generate_assets(output, _config) do
    Enum.each assets, fn({ pattern, dir }) ->
      output = "#{output}/#{dir}"
      File.mkdir output

      Enum.map Path.wildcard(pattern), fn(file) ->
        base = Path.basename(file)
        File.copy file, "#{output}/#{base}"
      end
    end
  end

  defp generate_extras(output, module_nodes, modules, exceptions, protocols, config) do
    extras =
      config.extras
      |> Enum.map(&Task.async(fn ->
          generate_extra(&1, output, module_nodes, modules, exceptions, protocols, config)
         end))
      |> Enum.map(&Task.await/1)
    [{"extra-api-reference", "API Reference", []}|extras]
  end

  defp generate_extra(input, output, module_nodes, modules, exceptions, protocols, config) do
    file_ext =
      input
      |> Path.extname
      |> String.downcase

    if file_ext in [".md"] do
      title = Path.rootname(Path.basename(input))
      file_name = title_to_filename(title)

      content =
        input
        |> File.read!
        |> Autolink.project_doc(module_nodes)

      html = Templates.extra_template(config, title, modules,
                                      exceptions, protocols, link_headers(content))

      File.write!("#{output}/#{file_name}.html", html)
      {file_name, title, extract_headers(content)}
    else
      raise ArgumentError, "file format not recognized, allowed format is: .md"
    end
  end

  @h2_regex ~r/^##([^#].*)$/m

  defp extract_headers(content) do
    Regex.scan(@h2_regex, content, capture: :all_but_first)
    |> List.flatten
    |> Enum.map(&{&1, header_to_id(&1)})
  end

  defp link_headers(content) do
    Regex.replace(@h2_regex, content, fn _, part ->
      "<h2 id=#{inspect header_to_id(part)}>#{part}</h2>"
    end)
  end

  defp title_to_filename(title) do
    "extra-" <> (title |> String.replace(" ", "-") |> String.downcase)
  end

  defp header_to_id(header) do
    header
    |> String.strip
    |> String.replace(~r/\W+/, "-")
  end

  defp process_logo_metadata(config) do
    output = "#{config.output}/assets"
    File.mkdir_p! output
    file_extname = Path.extname(config.logo) |> String.downcase

    if file_extname in ~w(.png .jpg) do
      file_name = "#{output}/logo#{file_extname}"
      File.copy!(config.logo, file_name)
      Map.put(config, :logo, Path.basename(file_name))
    else
      raise ArgumentError, "image format not recognized, allowed formats are: .jpg, .png"
    end
  end

  defp generate_redirect(output, file_name, config, redirect_to) do
    content = Templates.redirect_template(config, redirect_to)
    File.write!("#{output}/#{file_name}", content)
  end

  defp filter_list(:modules, nodes) do
    Enum.filter nodes, &(not &1.type in [:exception, :protocol, :impl])
  end

  defp filter_list(:exceptions, nodes) do
    Enum.filter nodes, &(&1.type in [:exception])
  end

  defp filter_list(:protocols, nodes) do
    Enum.filter nodes, &(&1.type in [:protocol])
  end

  defp generate_list(nodes, modules, exceptions, protocols, output, config) do
    nodes
    |> Enum.map(&Task.async(fn ->
        generate_module_page(&1, modules, exceptions, protocols, output, config)
       end))
    |> Enum.map(&Task.await/1)
  end

  defp generate_module_page(node, modules, exceptions, protocols, output, config) do
    content = Templates.module_page(node, modules, exceptions, protocols, config)
    File.write!("#{output}/#{node.id}.html", content)
  end

  defp templates_path(other) do
    Path.expand("html/templates/#{other}", __DIR__)
  end
end
