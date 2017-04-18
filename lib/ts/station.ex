defmodule Station do
	@moduledoc """
	Module to create a station process and FSM and handle local variable updates
	"""
	use GenStateMachine, async: true

	@doc """
	Start new Station process
	"""
	def start_link do
		GenStateMachine.start_link(Station, {:nodata, nil})
	end

	# Client-side getter and setter functions

	@doc """
	Update station struct values
	"""
	def update(station,  %StationStruct{}=new_vars) do
		GenStateMachine.cast(station, {:update, new_vars})
	end

	@doc """
	Return station struct values - local variables
	"""
	def get_vars(station) do
		GenStateMachine.call(station, :get_vars)
	end

	@doc """
	Return station struct values - state
	"""
	def get_state(station) do
		GenStateMachine.call(station, :get_state)
	end

	# Client-side message-passing functions

	@doc """
	Receive query at source station
	"""
	def receive_at_src(nc, src, itinerary) do
		GenStateMachine.cast(src, {:receive_at_src, nc, src, itinerary})
	end

	@doc """
	Send query to next station and append to itinerary
	"""
	def send_to_stn(nc, src, dst, itinerary) do
		GenStateMachine.cast(dst, {:receive_at_stn, nc, src, itinerary})
	end

	@doc """
	Check for valid next station
	"""
	def check_dest(dst, itinerary) do
		[_|tail]=itinerary
		dest_list=Enum.map(tail, fn (x)->x[:dst_station] end)
		!Enum.member?(dest_list, dst)
	end

	@doc """
	Return list of valid neighbouring stations
	"""
	def check_neighbours(schedule, other_means, time, itinerary) do
		# schedule is filtered to reject neighbours with departure time earlier
		# than arrival time at the station for the current itinerary
		time=if time>86_400 do
			time-86_400
		else
			time
		end
		[query]=Enum.take(itinerary, 1)
		neighbour_list=Enum.filter(schedule, fn(x)->x.dept_time>time&&
			check_dest(x.dst_station, itinerary)&&(query.day*86_400+x.arrival_time)<=
			query.end_time end)
		possible_walks=Enum.filter(other_means,
			fn(x)->check_dest(x.dst_station, itinerary) end)
		list=for x<-possible_walks do
			%{vehicleID: "OM", src_station: x.src_station, dst_station:
			x.dst_station, dept_time: time, arrival_time: time+x.travel_time,
			mode_of_transport: "Other Means"}
		end
		list=Enum.filter(list, fn(x)->(query.day*86_400+x.arrival_time)<=
			query.end_time end)
		List.flatten(list, neighbour_list)
	end

	@doc """
	Send query to neighbouring stations
	"""
	def function(nc, src, itinerary, dest_schedule) do
		# schedule to reach this destination station is added to itinerary
		new_itinerary=List.flatten([itinerary|[dest_schedule]])
		[query]=Enum.take(new_itinerary, 1)
		{:ok, {_, dst}}=StationConstructor.lookup_code(nc, dest_schedule.dst_station)
		# new_itinerary is either returned to NC or sent on to next station to
		# continue additions
		if dest_schedule.dst_station==query.dst_station do
			query=query|>Map.delete(:day)
			if API.member(query) do
				query|>API.get|>elem(1)|>QC.collect(new_itinerary)
			end
		else
			Station.send_to_stn(nc, src, dst, new_itinerary)
		end
	end

	# Server-side callback functions

	def handle_event(:cast, {:update, old_vars}, _, _) do
		# new_vars is assigned values passed to argument old_vars, ie, new values to
		# update local variables with
		schedule=Enum.sort(old_vars.schedule, &(&1.dept_time<=&2.dept_time))
		new_vars=%StationStruct{loc_vars: old_vars.loc_vars, schedule: schedule,
			other_means: old_vars.other_means, station_number: old_vars.station_number,
			station_name: old_vars.station_name, pid: old_vars.pid, congestion_low:
			old_vars.congestion_low, congestion_high:	old_vars.congestion_high,
			choose_fn: old_vars.choose_fn}
		# depending on the state of the station, appropriate FSM state change is
		# made and new values are stored for the station
		case(new_vars.loc_vars.disturbance) do
			"yes"->
				{:next_state, :disturbance, new_vars}
			"no"->
				case(new_vars.loc_vars.congestion) do
					"none"->
						{:next_state, :delay, new_vars}
					"low"->
						# congestion_delay is computed using computation function
						# selected based on the choose_fn value
						congestion_delay=StationFunctions.func(new_vars.choose_fn).
						(new_vars.loc_vars.delay, new_vars.congestion_low)
						{_, update_loc_vars}=Map.get_and_update(new_vars.loc_vars,
							:congestion_delay, fn delay->{delay, congestion_delay} end)
						update_vars=%{new_vars|loc_vars: update_loc_vars}
						{:next_state, :delay, update_vars}
					"high"->
						# congestion_delay is computed using computation function
						# selected based on the choose_fn value
						congestion_delay=StationFunctions.func(new_vars.choose_fn).
						(new_vars.loc_vars.delay, new_vars.congestion_high)
						{_, update_loc_vars}=Map.get_and_update(new_vars.loc_vars,
							:congestion_delay, fn delay->{delay, congestion_delay} end)
						update_vars=%{new_vars|loc_vars: update_loc_vars}
						{:next_state, :delay, update_vars}
					_->
						{:next_state, :delay, new_vars}
				end
			_->
				{:next_state, :delay, new_vars}
		end
	end

	def handle_event({:call, from}, :get_vars, state, vars) do
		# station variables values are returned
		{:next_state, state, vars, [{:reply, from, vars}]}
	end

	def handle_event({:call, from}, :get_state, state, vars) do
		# station FSM state is returned
		{:next_state, state, vars, [{:reply, from, state}]}
	end

	def handle_event(:cast, {:receive_at_src, nc, src, itinerary}, state, vars) do
		[query]=Enum.take(itinerary, 1)
		neighbour_list=Station.check_neighbours(vars.schedule, vars.other_means,
			query.arrival_time, itinerary)
		# for each neighbouring station, function is called to determine new
		# itinerary additions
		Enum.each(neighbour_list, fn(x)->function(nc, src, itinerary, x) end)
		{:next_state, state, vars}
	end

	def handle_event(:cast, {:receive_at_stn, nc, src, itinerary}, state, vars) do
		[query]=Enum.take(itinerary, 1)
		[prev_stn]=Enum.take(itinerary, -1)
		# check for overnight trip
		{itinerary, query}=if prev_stn.arrival_time>86_400 do
			itinerary=List.delete(itinerary, query)
			query=Map.update!(query, :day, &(&1+1))
			itinerary=List.insert_at(itinerary, 0, query)
			{itinerary, query}
		else
			{itinerary, query}
		end
		# check if query active
		_=if StationConstructor.check_active(nc, Map.delete(query, :day))===true do
			neighbour_list=Station.check_neighbours(vars.schedule, vars.other_means,
				prev_stn.arrival_time, itinerary)
			# for each neighbouring station, function is called to determine new
			# itinerary additions
			Enum.each(neighbour_list, fn(x)->function(nc, src, itinerary, x) end)
			true
		else
			false
		end
		{:next_state, state, vars}
	end

	def handle_event(event_type, event_content, state, vars) do
		super(event_type, event_content, state, vars)
	end

end
