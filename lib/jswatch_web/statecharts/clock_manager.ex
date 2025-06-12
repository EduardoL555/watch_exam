defmodule JswatchWeb.ClockManager do
  use GenServer

  # ——————————————————————————————————————————————
  # Formatea la fecha con blink en la parte seleccionada
  def format_date(date, show, selection) do
    day   = if date.day < 10, do: "0#{date.day}", else: "#{date.day}"
    month = ~w[ENE FEB MAR ABR MAY JUN JUL AGO SEP OCT NOV DIC]
            |> Enum.at(date.month - 1)
    year  = date.year - 2000

    {day, month, year} =
      case selection do
        :Day   -> {(if show, do: day, else: "  "), month, year}
        :Month -> {day, (if show, do: month, else: "   "), year}
        _      -> {day, month, (if show, do: year, else: "  ")}
      end

    "#{day}/#{month}/#{year}"
  end

  # ——————————————————————————————————————————————
  # Inicialización del GenServer y estado inicial
  def init(ui) do
    :gproc.reg({:p, :l, :ui_event})
    {_, now} = :calendar.local_time()
    date     = Date.utc_today()
    time     = Time.from_erl!(now)
    alarm    = Time.add(time, 10)

    # Arranca el cronómetro
    Process.send_after(self(), :working_working, 1_000)

    # Muestra hora y fecha inicial
    GenServer.cast(ui, {:set_time_display, Time.truncate(time, :second) |> Time.to_string()})
    GenServer.cast(ui, {:set_date_display, format_date(date, true, :Day)})

    state = %{
      ui_pid:    ui,
      time:      time,
      date:      date,
      alarm:     alarm,
      st1:       :Working,
      st2:       :Idle,
      selection: nil,
      show:      false,
      count:     0
    }

    {:ok, state}
  end

  # ——————————————————————————————————————————————
  # Cronómetro: solo avanza cuando NO estamos en edición (st2 == :Idle)
  def handle_info(:working_working,
      %{ui_pid: ui, time: time, alarm: alarm, st1: :Working, st2: :Idle} = state) do
    Process.send_after(self(), :working_working, 1_000)
    new_time = Time.add(time, 1)

    if new_time == alarm do
      :gproc.send({:p, :l, :ui_event}, :start_alarm)
    end

    GenServer.cast(ui, {:set_time_display, Time.truncate(new_time, :second) |> Time.to_string()})
    {:noreply, %{state | time: new_time}}
  end

  # ——————————————————————————————————————————————
  # Paso 1: al presionar bottom-right en Idle, entrar a modo Editing
  def handle_info({:ui_event, :'bottom-right-pressed'}, %{st2: :Idle} = state) do
    # 1) Detener working si hace falta
    state1 =
      if state.st1 == :Working do
        %{state | st1: :Stopped}
      else
        state
      end

    # 2) Configurar modo Editing (selección de día + blink)
    new_state = %{
      state1
      | st2:       :Editing,
        selection: :Day,
        show:      true,
        count:     0
    }

    # 3) Mostrar fecha con día parpadeando
    GenServer.cast(new_state.ui_pid, {:set_date_display, format_date(new_state.date, true, :Day)})

    # 4) Iniciar blink cada 250 ms
    Process.send_after(self(), :edit_blink, 250)

    {:noreply, new_state}
  end

  # En Idle, bottom-left no hace nada
  def handle_info({:ui_event, :'bottom-left-pressed'}, %{st2: :Idle} = state) do
    {:noreply, state}
  end

  # ——————————————————————————————————————————————
  # Paso 2: manejar el parpadeo en modo Editing
  def handle_info(:edit_blink,
      %{ui_pid: ui, date: date, selection: sel, show: show, count: count, st2: :Editing} = state) do
    new_show  = !show
    new_count = count + 1
    new_state = %{state | show: new_show, count: new_count}

    # Actualizar UI
    GenServer.cast(ui, {:set_date_display, format_date(date, new_show, sel)})

    # Reagendar siguiente blink
    Process.send_after(self(), :edit_blink, 250)

    {:noreply, new_state}
  end

  # ——————————————————————————————————————————————
  # Otros eventos ignorados
  def handle_info(_event, state), do: {:noreply, state}
end
