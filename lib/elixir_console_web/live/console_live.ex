defmodule ElixirConsoleWeb.ConsoleLive do
  @moduledoc """
  This is the main LiveView module of the application.
  """

  use Phoenix.LiveView
  import Phoenix.HTML, only: [sigil_e: 2]

  alias ElixirConsole.{Autocomplete, ContextualHelp, Sandbox}
  alias ElixirConsoleWeb.LiveMonitor

  defmodule Output do
    @enforce_keys [:command, :id]
    defstruct [:command, :result, :error, :id]
  end

  def render(assigns) do
    ~L"""
    <div class="flex h-full flex-col sm:flex-row">
      <div class="flex-1 sm:h-full overflow-scroll">
        <form phx-submit="execute" class="h-full flex flex-col">
          <div class="flex-1"></div>
          <div class="p-2" id="commandOutput" phx-update="append">
            <%= for output <- @output do %>
              <div id="command<%= output.id %>" class="text-gray-300 font-medium"><%= print_prompt() %><%= format_command(output.command) %></div>
              <div id="output<%= output.id %>" class="text-teal-300">
                <%= if output.result do output.result end %>
                <%= if output.error do %><span class="text-pink-400"><%= output.error %></span><% end %>
              </div>
            <% end %>
          </div>
          <div class="text-gray-300 font-medium flex bg-teal-700 p-2">
            <%= print_prompt() %>
            <input
              type="text"
              id="commandInput"
              class="ml-2 bg-transparent flex-1 outline-none"
              autocomplete="off"
              name="command"
              phx-keydown="suggest"
              phx-hook="CommandInput"
              data-input_value="<%= @input_value %>"
              data-caret_position="<%= @caret_position %>"
            />
          </div>
        </form>
      </div>
      <div class="w-full sm:w-32 md:w-1/3 h-32 sm:h-full bg-teal-800 text-gray-300 overflow-scroll flex flex-col">
        <div class="bg-teal-700 p-2 overflow-y-scroll max-h-1/3">
          <h2 class="font-medium">Current Bindings</h2>
          <ul>
            <%= if length(@sandbox.bindings) > 0 do %>
              <%= for {key, value} <- @sandbox.bindings do %>
                <li class="truncate"><%= key %>: <code class="text-teal-300"><%= inspect(value) %></code></li>
              <% end %>
            <% else %>
              <code class="text-teal-300 text-sm">No bindings yet!</code>
            <% end %>
          </ul>
        </div>
        <div class="flex-1 flex flex-col justify-end p-2">
          <%= if @suggestions != [] do %>
            <h2 class="font-medium">Suggestions:</h2>
          <% else %>
            <%= if @contextual_help do %>
              <span class="mb-8 font-bold text-green-400">
                <a href="<%= @contextual_help[:link] %>" target="_blank" class="underline"><%= @contextual_help[:func_name] %></a>
              </span>
              <span class="text-xs mb-4 font-bold text-gray-400"><%= @contextual_help[:header] %></span>
              <span class="contextual-help-doc text-xs text-gray-400"><%= Phoenix.HTML.raw @contextual_help[:doc] %></span>
            <% else %>
              <h2 class="underline mb-3">INSTRUCTIONS</h2>
              <p>[UP] [DOWN]: Navigate through commands history</p>
              <p>[TAB]: Get suggestions or autocomplete while typing</p>
              <p class="text-sm mt-3"> You can see the history panel that includes all your commands and their output.
              Click on any Elixir function to see here the corresponding documentation.</p>
              <h2 class="underline mt-5 mb-3">ABOUT SECURITY</h2>
              <p class="text-sm">Please note some features of the language are not safe to run in a shared environment like this console.
              If you are interested in knowing more about the limitations, you must <a class="underline" href="https://github.com/wyeworks/elixir_console#how-much-elixir-can-i-run-in-the-web-console">read here</a>.</p>
              <p class="text-sm">Please report any security vulnerabilities to
                <a class="underline" href="mailto:elixir-console-security@wyeworks.com">elixir-console-security@wyeworks.com<a>.
              </p>
            <% end %>
          <% end %>
          <ul>
            <%= for suggestion <- @suggestions do %>
              <li><%= suggestion %></li>
            <% end %>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  def mount(_session, socket) do
    sandbox = Sandbox.init()
    LiveMonitor.monitor(self(), __MODULE__, %{id: socket.id, sandbox: sandbox})

    {:ok,
     assign(
       socket,
       output: [],
       history: [],
       history_counter: 0,
       suggestions: [],
       input_value: "",
       caret_position: 0,
       contextual_help: nil,
       command_id: 0,
       sandbox: sandbox
     )}
  end

  @doc "Function invoked when the live view process is finished. See LiveMonitor.terminate/1."
  def unmount(%{sandbox: sandbox}) do
    Sandbox.terminate(sandbox)
  end

  # TAB KEY
  def handle_event("suggest", %{"keyCode" => 9, "value" => value}, socket) do
    %{caret_position: caret_position, sandbox: %{bindings: bindings}} = socket.assigns

    case Autocomplete.get_suggestions(value, caret_position, bindings) do
      [suggestion] ->
        {new_input, new_caret_position} =
          Autocomplete.autocompleted_input(value, caret_position, suggestion)

        {:noreply,
         assign(socket,
           suggestions: [],
           input_value: new_input,
           caret_position: new_caret_position
         )}

      suggestions ->
        {:noreply, assign(socket, suggestions: suggestions, input_value: "")}
    end
  end

  # KEY UP
  def handle_event("suggest", %{"keyCode" => 38}, socket) do
    counter = socket.assigns.history_counter
    history = socket.assigns.history

    {input_value, new_counter} =
      cond do
        history == [] ->
          {[], 0}

        counter + 1 < length(history) ->
          {[Enum.at(history, counter + 1)], counter + 1}

        counter + 1 >= length(history) ->
          {[List.last(history)], counter}
      end

    {:noreply, assign(socket, input_value: input_value, history_counter: new_counter)}
  end

  # KEY DOWN
  def handle_event("suggest", %{"keyCode" => 40}, socket) do
    counter = socket.assigns.history_counter
    history = socket.assigns.history

    {input_value, new_counter} =
      cond do
        history == [] ->
          {[], 0}

        counter > 0 ->
          {[Enum.at(history, counter - 1)], counter - 1}

        counter <= 0 ->
          {[List.first(history)], 0}
      end

    {:noreply, assign(socket, input_value: input_value, history_counter: new_counter)}
  end

  def handle_event("suggest", _key, socket) do
    {:noreply, assign(socket, history_counter: -1, input_value: "")}
  end

  def handle_event("caret-position", %{"position" => position}, socket) do
    {:noreply, assign(socket, caret_position: position)}
  end

  def handle_event("execute", %{"command" => command}, socket) do
    history =
      if socket.assigns.history == [] do
        [command]
      else
        [command | socket.assigns.history]
      end

    case execute_command(command, socket.assigns.sandbox) do
      {:ok, result, sandbox} ->
        {:noreply,
         socket
         |> append_output(:ok, command, result)
         |> assign(sandbox: sandbox)
         |> assign(history: history)
         |> assign(suggestions: [])
         |> assign(input_value: "")
         |> assign(contextual_help: nil)}

      {:error, error, sandbox} ->
        LiveMonitor.update_sandbox(self(), __MODULE__, %{id: socket.id, sandbox: sandbox})

        {:noreply,
         socket
         |> append_output(:error, command, error)
         |> assign(sandbox: sandbox)
         |> assign(history: history)
         |> assign(suggestions: [])
         |> assign(input_value: "")
         |> assign(contextual_help: nil)}
    end
  end

  def handle_event(
        "show_contextual_info",
        %{"func_name" => func_name, "header" => header, "doc" => doc, "link" => link},
        socket
      ) do
    {:noreply,
     socket
     |> assign(contextual_help: %{func_name: func_name, header: header, doc: doc, link: link})
     |> assign(suggestions: [])}
  end

  defp execute_command(command, sandbox) do
    case Sandbox.execute(command, sandbox) do
      {:success, {result, sandbox}} ->
        {:ok, inspect(result), sandbox}

      {:error, {error_string, sandbox}} ->
        {:error, error_string, sandbox}
    end
  end

  defp append_output(socket, status, command, result_or_error) do
    socket
    |> assign(output: [build_output(status, command, result_or_error, socket.assigns.command_id)])
    |> assign(command_id: socket.assigns.command_id + 1)
  end

  defp build_output(:ok, command, result, id),
    do: %Output{command: command, result: result, id: id}

  defp build_output(:error, command, error, id),
    do: %Output{command: command, error: error, id: id}

  defp print_prompt, do: "> "

  defp format_command(command) do
    for part <- split_command(command) do
      case part do
        {part, help_metadata} ->
          render_command_inline_help(part, help_metadata)

        part ->
          part
      end
    end
  end

  defp split_command(command) do
    ContextualHelp.compute(command)
  end

  defp render_command_inline_help(part, %{
         type: function_or_operator,
         func_name: func_name,
         header: header,
         docs: docs,
         link: link
       }) do
    ~e{<span
      phx-click="show_contextual_info"
      phx-value-func_name="<%= func_name %>"
      phx-value-header="<%= header %>"
      phx-value-doc="<%= docs %>"
      phx-value-link="<%= link %>"
      class="<%= inline_help_class_for(function_or_operator) %>"
    ><%= part %></span>}
  end

  defp inline_help_class_for(:function), do: "text-green-400 cursor-pointer underline"
  defp inline_help_class_for(:operator), do: "cursor-pointer"
end
