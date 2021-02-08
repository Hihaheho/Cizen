defmodule Cizen.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      # Starts a worker by calling: Cizen.Worker.start_link(arg)
      %{
        id: Cizen.Dispatcher,
        start: {Cizen.Dispatcher, :start_link, []}
      },
      %{
        id: Cizen.CizenSagaRegistry,
        start: {Cizen.CizenSagaRegistry, :start_link, []}
      }
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Cizen.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def start_phase(:start_children, _start_type, _args) do
    Supervisor.start_child(Cizen.Supervisor, %{
      id: Cizen.Dispatcher.Node,
      start: {Cizen.Dispatcher.Node, :start_root_node, []}
    })

    Supervisor.start_child(Cizen.Supervisor, %{
      id: Cizen.SagaLauncher,
      start: {Cizen.SagaLauncher, :start_link, []}
    })

    Supervisor.start_child(Cizen.Supervisor, %{
      id: Cizen.SagaResumer,
      start: {Cizen.SagaResumer, :start_link, []}
    })

    Supervisor.start_child(Cizen.Supervisor, %{
      id: Cizen.SagaMonitor,
      start: {Cizen.SagaMonitor, :start_link, []}
    })

    :ok
  end

  def start_phase(:start_daemons, _start_type, _args) do
    alias Cizen.Saga

    daemon_sagas = [
      %Cizen.CrashLogger{}
    ]

    Enum.each(daemon_sagas, fn saga ->
      Supervisor.start_child(Cizen.Supervisor, %{
        id: Saga.module(saga),
        start: {Saga, :start_link, [saga]}
      })
    end)

    :ok
  end
end
