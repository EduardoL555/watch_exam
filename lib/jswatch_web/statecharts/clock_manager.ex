defmodule JswatchWeb.ClockManager do
  use GenServer

  def format_date(date, show, selection) do
    day = if date.day < 10, do: "0#{date.day}", else: "#{date.day}"
    month = ~w[ENE FEB MAR ABR MAY JUN JUL AGO SEP OCT NOV DIC] |> Enum.at(date.month - 1)
    year = date.year - 2000
    {day,month,year} =
      case selection do
        Day -> {(if show, do: day, else: "  "), month, year}
        Month -> {day, (if show, do: month, else: "   "), year}
        _ -> {day, month, (if show, do: year, else: "  ")}
      end
    "#{day}/#{month}/#{year}"
  end

def init(ui) do
  :gproc.reg({:p, :l, :ui_event})
  {_, now} = :calendar.local_time()
  date = Date.utc_today()
  time = Time.from_erl!(now)
  alarm = Time.add(time, 10)

  Process.send_after(self(), :working_working, 1000)
  GenServer.cast(ui, {:set_time_display, Time.truncate(time, :second) |> Time.to_string })
  GenServer.cast(ui, {:set_date_display, format_date(date, true, Day) })

  {:ok,
    %{
      ui_pid:    ui,
      time:      time,
      date:      date,
      alarm:     alarm,
      st1:       Working,
      st2:       Idle,
      selection: nil,
      show:      false,
      count:     0
    }
  }
end


  def handle_info(:working_working, %{ui_pid: ui, time: time, alarm: alarm, st1: Working} = state) do
    Process.send_after(self(), :working_working, 1000)
    time = Time.add(time, 1)
    if time == alarm do
      :gproc.send({:p, :l, :ui_event}, :start_alarm)
    end
    GenServer.cast(ui, {:set_time_display, Time.truncate(time, :second) |> Time.to_string })
    {:noreply, state |> Map.put(:time, time) }
  end

  # Paso 1: bottom-right en Idle → entrar a Editing
def handle_info({:ui_event, :'bottom-right-pressed'}, %{st2: Idle} = state) do
  # 1) Detener Working si aplica
  state1 =
    if state.st1 == Working do
      %{state | st1: Stopped}
    else
      state
    end

  # 2) Preparar modo Editing
  new_state = %{
    state1
    | st2:       Editing,
      selection: Day,
      show:      true,
      count:     0
  }

  # 3) Mostrar fecha con día parpadeando
  GenServer.cast(new_state.ui_pid, {:set_date_display, format_date(new_state.date, true, Day)})

  # 4) Arrancar blink cada 250 ms
  Process.send_after(self(), :edit_blink, 250)

  {:noreply, new_state}
end

# Idle: bottom-left no hace nada
def handle_info({:ui_event, :'bottom-left-pressed'}, %{st2: Idle} = state) do
  {:noreply, state}
end


  def handle_info(_event, state), do: {:noreply, state}
end
