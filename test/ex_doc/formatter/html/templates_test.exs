defmodule ExDoc.Formatter.HTML.TemplatesTest do
  use ExUnit.Case, async: true

  alias ExDoc.Formatter.HTML
  alias ExDoc.Formatter.HTML.Templates

  import ExDoc.TestHTMLHelpers

  defp source_url do
    "https://github.com/elixir-lang/elixir"
  end

  defp homepage_url do
    "http://elixir-lang.org"
  end

  defp doc_config do
    %ExDoc.Config{
      project: "Elixir",
      version: "1.0.1",
      source_root: File.cwd!,
      source_url_pattern: "#{source_url}/blob/master/%{path}#L%{line}",
      homepage_url: homepage_url,
      source_url: source_url,
    }
  end

  defp get_module_page(names) do
    mods = names
           |> ExDoc.Retriever.docs_from_modules(doc_config)
           |> HTML.Autolink.all()

    Templates.module_page(hd(mods), doc_config, mods, false)
  end

  ## LISTING

  test "site title text links to homepage_url when set" do
    content = Templates.sidebar_template(doc_config, [], [], [], false)

    titleLink = find_elem content, "h1 a"
    version = find_elem content, "h2"

    assert_text titleLink, "Elixir"
    assert_text version, "v1.0.1"

    assert_attribute titleLink, "href", homepage_url
  end

  test "Disable nav links when module type is empty" do
    content = Templates.sidebar_template(doc_config, [], [], [], false)

    links = Floki.find(content, ".sidebar-mainNav li")

    Enum.drop(links, 1)
      |> assert_attribute "class", "disabled"
  end

  test "Enable nav link when module type have at least one element" do
    names = [CompiledWithDocs, CompiledWithDocs.Nested]
    nodes = ExDoc.Retriever.docs_from_modules(names, doc_config)
    all = HTML.Autolink.all(nodes)
    modules    = HTML.filter_list(:modules, all)
    exceptions = HTML.filter_list(:exceptions, all)
    protocols  = HTML.filter_list(:protocols, all)

    content = Templates.sidebar_template(doc_config, modules, exceptions, protocols, false)

    links = Floki.find(content, ".sidebar-mainNav li")
    moduleLink = Enum.at(links, 1)

    assert Floki.attribute(moduleLink, "class") === []

    Enum.drop(links, 2)
      |> assert_attribute "class", "disabled"
  end

  test "site title text links to source_url when there is no homepage_url" do
    config = %ExDoc.Config{project: "Elixir",
                           version: "1.0.1",
                           source_root: File.cwd!,
                           source_url: source_url,
                           source_url_pattern: "#{source_url}/blob/master/%{path}#L%{line}"}

    content = Templates.sidebar_template(config, [], [], [], false)
    titleLink = find_elem content, ".sidebar-projectName a"

    assert_attribute titleLink, "href", source_url
  end

  test "site title text creates no link when there is no homepage_url or source_url" do
    config = %ExDoc.Config{project: "Elixir",
                           version: "1.0.1",
                           source_root: File.cwd!,
                           source_url_pattern: "#{source_url}/blob/master/%{path}#L%{line}"}

    content = Templates.sidebar_template(config, [], [], [], false)
    title = find_elem content, ".sidebar-projectName"

    assert_text title, "Elixir"
    assert Floki.find(title, "a") === []
  end

  test "list_page outputs listing for the given nodes" do
    names = [CompiledWithDocs, CompiledWithDocs.Nested]
    nodes = ExDoc.Retriever.docs_from_modules(names, doc_config)
    content = Templates.create_sidebar_items([%{id: "modules", value: nodes}])

    assert content =~ ~r{.*\"id\":\s*\"CompiledWithDocs\".*}ms
    assert content =~ ~r{.*\"id\":\s*\"CompiledWithDocs\".*\"functions\".*\"example/2\".*}ms
    assert content =~ ~r{.*\"id\":\s*\"CompiledWithDocs\".*\"macros\".*\"example_1/0\".*}ms
    assert content =~ ~r{.*\"id\":\s*\"CompiledWithDocs\".*\"functions\".*\"example_without_docs/0\".*}ms
    assert content =~ ~r{.*"CompiledWithDocs.Nested\"}ms # fix emacs highlighting "
    refute content =~ ~r{.*\"exceptions\":}ms
    refute content =~ ~r{.*\"protocols\":}ms
  end

  test "listing page has README link if present" do
    content = Templates.sidebar_template(doc_config, [], [], [], true)
    links = Floki.find(content, ".sidebar-mainNav li")

    assert_text Enum.at(links, 0), "README"
  end

  test "listing page doesn't have README link if not present" do
    content = Templates.sidebar_template(doc_config, [], [], [], false)
    links = Floki.find(content, ".sidebar-mainNav li")

    assert_text Enum.at(links, 0), "Overview"
  end

  ## MODULES

  test "module_page generates only the module name when there's no more info" do
    node = %ExDoc.ModuleNode{module: XPTOModule, moduledoc: nil, id: "XPTOModule"}
    content = Templates.module_page(node, doc_config, [node], false)

    assert content =~ ~r{<title>XPTOModule [^<]*</title>}
    assert content =~ ~r{<h1>\s*XPTOModule\s*</h1>}
  end

  test "module_page outputs the functions and docstrings" do
    content = get_module_page([CompiledWithDocs])

    assert content =~ ~r{<title>CompiledWithDocs [^<]*</title>}
    assert content =~ ~r{<h1>\s*CompiledWithDocs\s*}
    assert content =~ ~r{moduledoc.*Example.*CompiledWithDocs\.example.*}ms
    assert content =~ ~r{example/2.*Some example}ms
    assert content =~ ~r{example_without_docs/0.*<section class="docstring">.*</section>}ms
    assert content =~ ~r{example_1/0.*Another example}ms
    assert content =~ ~r{<a href="#{source_url}/blob/master/test/fixtures/compiled_with_docs.ex#L10"[^>]*>\n\s*<i class="fa fa-code"></i>\n\s*</a>}ms

    assert content =~ ~s{<div class="detail-header" id="example_1/0">}
    assert content =~ ~s{example(foo, bar \\\\ Baz)}
    assert content =~ ~r{<a href="#example/2" class="detail-link" title="Link to this function">\n\s*<i class="fa fa-link"><\/i>\n\s*<\/a>}ms
  end

  test "module_page outputs the types and function specs" do
    content = get_module_page([TypesAndSpecs, TypesAndSpecs.Sub])

    mb = "http://elixir-lang.org/docs/stable"

    public_html =
      "<a href=\"#t:public/1\">public(t)</a> :: {t, " <>
      "<a href=\"#{mb}/elixir/String.html#t:t/0\">String.t</a>, " <>
      "<a href=\"TypesAndSpecs.Sub.html#t:t/0\">TypesAndSpecs.Sub.t</a>, " <>
      "<a href=\"#t:opaque/0\">opaque</a>, :ok | :error}"

    ref_html = "<a href=\"#t:ref/0\">ref</a> :: " <>
               "{:binary.part, <a href=\"#t:public/1\">public(any)</a>}"

    assert content =~ ~s[<a href="#t:public/1">public(t)</a>]
    refute content =~ ~s[<a href="#t:private/0">private</a>]
    assert content =~ public_html
    assert content =~ ref_html
    refute content =~ ~s[<strong>private\(t\)]
    assert content =~ ~s[A public type]
    assert content =~ ~s[add(integer, <a href="#t:opaque/0">opaque</a>) :: integer]
    refute content =~ ~s[minus(integer, integer) :: integer]
  end

  test "module_page outputs summaries" do
    content = get_module_page([CompiledWithDocs])
    assert content =~ ~r{<div class="summary-signature">\s*<a href="#example_1/0">}
  end

  test "module_page contains links to summary sections when those exist" do
    content = get_module_page([CompiledWithDocs, CompiledWithDocs.Nested])
    assert content =~ ~r{<a href="#summary_details">Summary</a>}
    refute content =~ ~r{types_details}
  end

  ## BEHAVIOURS

  test "module_page outputs behavior and callbacks" do
    content = get_module_page([CustomBehaviourOne])
    assert content =~ ~r{<h1>\s*CustomBehaviourOne\s*<small>behaviour</small>}m
    assert content =~ ~r{Callbacks}
    assert content =~ ~r{<div class="detail-header" id="c:hello/1">}

    content = get_module_page([CustomBehaviourTwo])
    assert content =~ ~r{<h1>\s*CustomBehaviourTwo\s*<small>behaviour</small>\s*}m
    assert content =~ ~r{Callbacks}
    assert content =~ ~r{<div class="detail-header" id="c:bye/1">}
  end

  ## PROTOCOLS

  test "module_page outputs the protocol type" do
    content = get_module_page([CustomProtocol])
    assert content =~ ~r{<h1>\s*CustomProtocol\s*<small>protocol</small>\s*}m
  end
end
