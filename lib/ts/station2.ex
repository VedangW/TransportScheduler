# Module to create station process and FSM and handle local variable updates

defmodule Station2 do
  use GenStateMachine

  # Client

  def start_link() do
    GenStateMachine.start_link(Station, {:nodata, nil})
  end

  def update(station, newVars) do
    GenStateMachine.cast(station, newVars)
  end

  def get_vars(station) do
    GenStateMachine.call(station, :get_vars)
  end
  
  def get_state(station) do
    GenStateMachine.call(station, :get_state)
  end

  # Server (callbacks)

  def handle_event(:cast, newVars, state, vars) do
		case(newVars.disturbance) do
			"yes"	->
				{:next_state, :disturbance, newVars}
			"no"	-> 
				case(newVars.congestion) do
					"none"	->
						{:next_state, :delay, newVars}
					"low"		->
						updateVars = %{newVars | :delay => Map.get(newVars, :delay) * 2.0}
						{:next_state, :delay, updateVars}
					"high"	->
						updateVars = %{newVars | :delay => Map.get(newVars, :delay) * 3.0}
						{:next_state, :delay, updateVars}
					_				->
						{:next_state, :delay, newVars}	
				end
			_			->
				{:next_state, :delay, newVars}
		end          
  end

  def handle_event({:call, from}, :get_vars, state, vars) do
    {:next_state, state, vars, [{:reply, from, vars}]}
  end

  def handle_event({:call, from}, :get_state, state, vars) do
    {:next_state, state, vars, [{:reply, from, state}]}
  end

  def handle_event(event_type, event_content, state, vars) do
    # Call the default implementation from GenStateMachine
    super(event_type, event_content, state, vars)
  end
end
