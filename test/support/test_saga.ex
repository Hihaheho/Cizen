defmodule Cizen.TestSaga do
  @moduledoc false
  use Cizen.Saga

  defstruct [:on_start, :on_resume, :handle_event, :state, :extra]

  @impl true
  def on_start(%__MODULE__{on_start: on_start, handle_event: handle_event, state: state} = struct) do
    on_start = on_start || fn state -> state end
    handle_event = handle_event || fn _, state -> state end
    state = on_start.(state)
    %__MODULE__{struct | on_start: on_start, handle_event: handle_event, state: state}
  end

  @impl true
  def on_resume(%__MODULE__{on_resume: on_resume, handle_event: handle_event} = struct, state) do
    on_resume = on_resume || fn _, _ -> state end
    handle_event = handle_event || fn _, state -> state end
    state = on_resume.(struct, state)
    %__MODULE__{struct | on_resume: on_resume, handle_event: handle_event, state: state}
  end

  @impl true
  def handle_event(event, %__MODULE__{handle_event: handle_event, state: state} = struct) do
    state = handle_event.(event, state)
    %__MODULE__{struct | state: state}
  end
end
