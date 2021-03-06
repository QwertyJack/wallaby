defmodule Wallaby.Experimental.Chrome do
  use Supervisor
  @behaviour Wallaby.Driver

  @chromedriver_version_regex ~r/^ChromeDriver 2\.(\d+).(\d+) \(.*\)/

  alias Wallaby.Session
  alias Wallaby.Experimental.Chrome.{Chromedriver}
  alias Wallaby.Experimental.Selenium.WebdriverClient

  @doc false
  def start_link(opts\\[]) do
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    children = [
      worker(Wallaby.Experimental.Chrome.Chromedriver, [])
    ]

    supervise(children, strategy: :one_for_one)
  end

  def validate() do
    case System.find_executable("chromedriver") do
      chromedriver when not is_nil(chromedriver) ->
        {version, 0} = System.cmd("chromedriver", ["--version"])
        version =
          Regex.run(@chromedriver_version_regex, version)
          |> Enum.at(1)
          |> String.to_integer

        if version >= 30 do
          :ok
        else
          exception = Wallaby.DependencyException.exception """
          Looks like you're trying to run an older version of chromedriver. Wallaby needs at least
          chromedriver 2.30 to run correctly.
          """
          {:error, exception}
        end
      _ ->
        exception = Wallaby.DependencyException.exception """
        Wallaby can't find chromedriver. Make sure you have chromedriver installed
        and included in your path.
        """
        {:error, exception}
    end
  end

  def start_session(opts) do
    {:ok, base_url} = Chromedriver.base_url()
    create_session_fn = Keyword.get(opts, :create_session_fn,
                                    &WebdriverClient.create_session/2)
    user_agent = user_agent()
                 |> Wallaby.Metadata.append(opts[:metadata])
    capabilities = capabilities(user_agent: user_agent)

    with {:ok, response} <- create_session_fn.(base_url, capabilities) do
      id = response["sessionId"]

      session = %Wallaby.Session{
        session_url: base_url <> "session/#{id}",
        url: base_url <> "session/#{id}",
        id: id,
        driver: __MODULE__,
        server: Chromedriver,
      }

      {:ok, session}
    end
  end

  def end_session(%Wallaby.Session{}=session, opts \\ []) do
    end_session_fn = Keyword.get(opts, :end_session_fn, &WebdriverClient.delete_session/1)
    end_session_fn.(session)
    :ok
  end

  def blank_page?(session) do
    case current_url(session) do
      {:ok, url} ->
        url == "data:,"
      _ ->
        false
    end
  end

  def get_window_size(%Session{} = session) do
    handle = WebdriverClient.window_handle(session)
    WebdriverClient.get_window_size(session, handle)
  end

  def set_window_size(session, width, height) do
    handle = WebdriverClient.window_handle(session)
    WebdriverClient.set_window_size(session, handle, width, height)
  end

  def accept_dialogs(_session), do: {:error, :not_implemented}
  def dismiss_dialogs(_session), do: {:error, :not_implemented}
  
  defdelegate accept_alert(session, fun),                        to: WebdriverClient
  defdelegate dismiss_alert(session, fun),                       to: WebdriverClient
  defdelegate accept_confirm(session, fun),                      to: WebdriverClient  
  defdelegate dismiss_confirm(session, fun),                     to: WebdriverClient
  defdelegate accept_prompt(session, input, fun),                to: WebdriverClient
  defdelegate dismiss_prompt(session, fun),                      to: WebdriverClient


  @doc false
  defdelegate cookies(session),                                   to: WebdriverClient
  @doc false
  defdelegate current_path(session),                              to: WebdriverClient
  @doc false
  defdelegate current_url(session),                               to: WebdriverClient
  @doc false
  defdelegate page_title(session),                                to: WebdriverClient
  @doc false
  defdelegate page_source(session),                               to: WebdriverClient
  @doc false
  defdelegate set_cookie(session, key, value),                    to: WebdriverClient
  @doc false
  defdelegate visit(session, url),                                to: WebdriverClient

  @doc false
  defdelegate attribute(element, name),                           to: WebdriverClient
  @doc false
  defdelegate click(element),                                     to: WebdriverClient
  @doc false
  defdelegate clear(element),                                     to: WebdriverClient
  @doc false
  defdelegate displayed(element),                                 to: WebdriverClient
  @doc false
  defdelegate selected(element),                                  to: WebdriverClient
  @doc false
  defdelegate set_value(element, value),                          to: WebdriverClient
  @doc false
  defdelegate text(element),                                      to: WebdriverClient

  @doc false
  defdelegate execute_script(session_or_element, script, args),   to: WebdriverClient
  @doc false
  defdelegate find_elements(session_or_element, compiled_query),  to: WebdriverClient
  @doc false
  defdelegate send_keys(session_or_element, keys),                to: WebdriverClient
  @doc false
  defdelegate take_screenshot(session_or_element),                to: WebdriverClient

  @doc false
  def user_agent do
    "Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2228.0 Safari/537.36"
  end

  defp capabilities(opts) do
    default_capabilities()
    |> Map.put(:chromeOptions, chrome_options(opts))
  end

  defp default_capabilities do
    %{
      javascriptEnabled: false,
      loadImages: false,
      version: "",
      rotatable: false,
      takesScreenshot: true,
      cssSelectorsEnabled: true,
      nativeEvents: false,
      platform: "ANY",
      unhandledPromptBehavior: "accept",
    }
  end

  defp chrome_options(opts), do: %{
      args: chrome_args(opts)
    }

  defp chrome_args(opts) do
    default_chrome_args()
    |> Enum.concat(headless_args())
    |> Enum.concat(user_agent_arg(opts[:user_agent]))
  end

  defp user_agent_arg(nil), do: []
  defp user_agent_arg(ua), do: ["--user-agent=#{ua}"]

  defp headless? do
    :wallaby
    |> Application.get_env(:chrome, [])
    |> Keyword.get(:headless, true)
  end

  def default_chrome_args() do
    [
      "--no-sandbox",
      "window-size=1280,800",
      "--disable-gpu",
    ]
  end

  defp headless_args() do
    if headless?() do
      ["--fullscreen", "--headless"]
    else
      []
    end
  end

end
