defmodule BeaconWeb.Layouts do
  @moduledoc false

  use BeaconWeb, :html
  require Logger

  embed_templates "layouts/*"

  # TODO: style nonce
  def asset_path(conn, asset) when asset in [:css, :js] do
    %{assigns: %{__site__: site}} = conn
    prefix = router(conn).__beacon_scoped_prefix_for_site__(site)

    hash =
      cond do
        asset == :css -> Beacon.RuntimeCSS.current_hash(site)
        asset == :js -> Beacon.RuntimeJS.current_hash()
      end

    path = Beacon.Router.sanitize_path("#{prefix}/beacon_assets/#{asset}-#{hash}")
    Phoenix.VerifiedRoutes.unverified_path(conn, conn.private.phoenix_router, path)
  end

  defp router(%Plug.Conn{private: %{phoenix_router: router}}), do: router
  defp router(%Phoenix.LiveView.Socket{router: router}), do: router

  def dynamic_layout?(%{__dynamic_layout_id__: _}), do: true
  def dynamic_layout?(_), do: false

  def render_dynamic_layout(%{__dynamic_layout_id__: layout_id} = assigns) do
    layout_id
    |> Beacon.Loader.layout_module_for_site()
    |> Beacon.Loader.call_function_with_retry!(:render, [assigns])
  end

  def live_socket_path(%{__site__: site}) do
    Beacon.Config.fetch!(site).live_socket_path
  end

  defp compiled_page_assigns(page_id) do
    page_id
    |> Beacon.Loader.page_module_for_site()
    |> Beacon.Loader.call_function_with_retry!(:page_assigns, [])
  end

  defp compiled_layout_assigns(layout_id) do
    layout_id
    |> Beacon.Loader.layout_module_for_site()
    |> Beacon.Loader.call_function_with_retry!(:layout_assigns, [])
  end

  def render_page_title(assigns) do
    BeaconWeb.DataSource.page_title(assigns)
  end

  def page_title(%{__dynamic_layout_id__: layout_id, __dynamic_page_id__: page_id}) do
    %{title: page_title} =
      page_id
      |> Beacon.Loader.page_module_for_site()
      |> Beacon.Loader.call_function_with_retry!(:page_assigns, [])

    if page_title do
      page_title
    else
      %{title: layout_title} =
        layout_id
        |> Beacon.Loader.layout_module_for_site()
        |> Beacon.Loader.call_function_with_retry!(:layout_assigns, [])

      layout_title || missing_page_title()
    end
  end

  def page_title(_), do: missing_page_title()

  defp missing_page_title do
    Logger.warning("no page title was found")
    ""
  end

  def render_meta_tags(assigns) do
    ~H"""
    <%= for meta_attributes <- BeaconWeb.DataSource.meta_tags(assigns) do %>
      <meta {meta_attributes} />
    <% end %>
    """
  end

  def meta_tags(assigns) do
    page_meta_tags = page_meta_tags(assigns) || []
    layout_meta_tags = layout_meta_tags(assigns) || []

    (page_meta_tags ++ layout_meta_tags)
    |> Enum.reject(&(&1["name"] == "csrf-token"))
    |> Kernel.++(Beacon.Content.default_site_meta_tags())
  end

  defp page_meta_tags(%{page_assigns: %{meta_tags: meta_tags}} = assigns) do
    assigns
    |> compiled_page_meta_tags()
    |> Map.merge(meta_tags)
  end

  defp page_meta_tags(assigns) do
    compiled_page_meta_tags(assigns)
  end

  defp compiled_page_meta_tags(%{__dynamic_page_id__: page_id}) do
    %{meta_tags: meta_tags} = compiled_page_assigns(page_id)
    meta_tags
  end

  defp layout_meta_tags(%{layout_assigns: %{meta_tags: meta_tags}} = assigns) do
    assigns
    |> compiled_layout_meta_tags()
    |> Map.merge(meta_tags)
  end

  defp layout_meta_tags(assigns) do
    compiled_layout_meta_tags(assigns)
  end

  defp compiled_layout_meta_tags(%{__dynamic_layout_id__: layout_id}) do
    %{meta_tags: meta_tags} = compiled_layout_assigns(layout_id)
    meta_tags
  end

  def render_schema(%{__dynamic_page_id__: page_id} = assigns) do
    %{raw_schema: raw_schema} =
      page_id
      |> Beacon.Loader.page_module_for_site()
      |> Beacon.Loader.call_function_with_retry!(:page_assigns, [])

    is_empty = fn raw_schema ->
      raw_schema |> Enum.map(&Map.values/1) |> List.flatten() == []
    end

    if is_empty.(raw_schema) do
      []
    else
      assigns = assign(assigns, :raw_schema, Jason.encode!(raw_schema))

      ~H"""
      <script type="application/ld+json">
        <%= {:safe, @raw_schema} %>
      </script>
      """
    end
  end

  def render_resource_links(%{__dynamic_layout_id__: _, __site__: _} = assigns) do
    resource_links = layout_resource_links(assigns) || []
    assigns = assign(assigns, :resource_links, resource_links)

    ~H"""
    <%= for attr <- @resource_links do %>
      <link {attr} />
    <% end %>
    """
  end

  def render_resource_links(_assigns), do: []

  defp layout_resource_links(%{layout_assigns: %{resource_links: resource_links}} = assigns) do
    assigns
    |> compiled_layout_resource_links()
    |> Map.merge(resource_links)
  end

  defp layout_resource_links(assigns) do
    compiled_layout_resource_links(assigns)
  end

  defp compiled_layout_resource_links(%{__dynamic_layout_id__: layout_id}) do
    %{resource_links: resource_links} = compiled_layout_assigns(layout_id)
    resource_links
  end
end
