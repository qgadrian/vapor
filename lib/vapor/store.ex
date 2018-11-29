defmodule Vapor.Store do
  use GenServer

  def start_link({module, plans}) do
    GenServer.start_link(__MODULE__, {module, plans}, name: module)
  end

  def set(address, key, value) when is_binary(key) do
    GenServer.call(address, {:set, key, value})
  end

  def get(module, key, as: type) when is_binary(key) do
    case :ets.lookup(module, key) do
      [] ->
        {:error, Vapor.NotFoundError}

      [{^key, value}] ->
        Vapor.Config.Converter.apply(value, type)
    end
  end

  def init({module, plan}) do
    ^module = :ets.new(module, [:set, :protected, :named_table])

    case load_config(module, plan) do
      :ok ->
        {:ok, %{plan: plan, table: module}}

      :error ->
        {:stop, :could_not_load_config}
    end
  end

  def handle_call({:set, key, value}, _from, %{table: tab} = state) do
    :ets.insert(tab, {key, value})

    {:reply, {:ok, value}, state}
  end

  defp load_config(table, plans, retry_count \\ 0)
  defp load_config(_table, [], _), do: :ok
  defp load_config(_table, _, 10), do: :error

  defp load_config(table, [plan | rest], retry_count) do
    case Vapor.Provider.load(plan) do
      {:ok, configs} ->
        Enum.each(configs, fn k_v ->
          :ets.insert(table, k_v)
        end)

        load_config(table, rest, 0)

      {:error, _e} ->
        load_config(table, [plan | rest], retry_count + 1)
    end
  end
end
