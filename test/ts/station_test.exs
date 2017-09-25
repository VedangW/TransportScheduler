defmodule StationTest do
	@moduledoc"""
	Module to test Station.
	Create new station process with associated FSM and updates local variable
	values. It also tests the interaction of one station with the others.
	It also tests the validity of a query and the interaction of the Station
	with the Query Collector.
	"""
	use ExUnit.Case

	# Test to see if the given state is stored by updating 
	# some variables
	test "stores the given state" do
		# Start the server
		{:ok, station} = Station.start_link

		# Update variables in station
		Station.update(station, %StationStruct{loc_vars: %{"delay": 0.38,
			"congestion": "low", "disturbance": "no"},
			schedule: [], congestion_low: 4, choose_fn: 1})

		# Verify values from StationStruct
		assert Station.get_vars(station).loc_vars.delay == 0.38
		assert Station.get_vars(station).loc_vars.congestion_delay == 0.38 * 4
		assert Station.get_state(station) == :delay
	end

	# Test to see if data can be retrieved from the station correctly
	test "retrieving the given state" do
		# Start the server
		{:ok, station} = Station.start_link

		# Update variables in station
		Station.update(station, %StationStruct{loc_vars: %{"delay": 0.12,
			"congestion": "low", "disturbance": "no"},
			schedule: [], station_number: 1710, 
			station_name: "Mumbai", congestion_low: 3, choose_fn: 2})

		# Retrieve values from loc_vars
		assert Station.get_vars(station).loc_vars.delay == 0.12
		assert Station.get_vars(station).loc_vars.congestion == "low"
		assert Station.get_vars(station).loc_vars.disturbance == "no"

		# Retrieve other values from StationStruct
		assert Station.get_vars(station).station_number == 1710
		assert Station.get_vars(station).station_name == "Mumbai"
		assert Station.get_vars(station).congestion_delay == 0.12 * 3 + 0.2
	end

	# Test to see if the state gets updated once new variable 
	# values are given
	test "updating the given state" do
		# Start the server
		{:ok, station} = Station.start_link

		# Update variables in station
		Station.update(station, %StationStruct{loc_vars: %{"delay": 0.38,
			"congestion": "low", "disturbance": "no"},
			schedule: [], congestion_low: 4, choose_fn: 1})

		# Check to see if change has taken place
		assert Station.get_vars(station).loc_vars.congestion_delay == 0.38 * 4

		# Update state again
		Station.update(station, %StationStruct{loc_vars: %{"delay": 0.0,
			"congestion": "none", "disturbance": "no"},
			schedule: [], station_name: "Panjim", choose_fn: 1})

		# Check to see if update has taken place
		assert Station.get_vars(station).loc_vars.disturbance == "no"
		assert Station.get_vars(station).loc_vars.congestion_delay == 0.0
		assert Station.get_vars(station).station_name == "Panjim"
	end
end