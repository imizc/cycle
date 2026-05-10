--[[
	Cycle
	A generic round management library for Roblox.
	Handles intermission, map voting, team assignment, round timing, and win conditions.

	Author: isaac (in_fss)
	GitHub: github.com/imizc
--]]

local Players = game:GetService("Players")
local Teams   = game:GetService("Teams")

local Cycle = {}
Cycle.__index = Cycle

-- valid round states in order
local STATES = {
	INTERMISSION = "Intermission",
	MAP_VOTE     = "MapVote",
	LOADING      = "Loading",
	IN_ROUND     = "InRound",
	END_SCREEN   = "EndScreen",
}
Cycle.States = STATES

-- default configuration
local DEFAULTS = {
	IntermissionDuration = 20,   -- seconds in lobby before map vote
	MapVoteDuration      = 15,   -- seconds players have to vote
	LoadingDuration      = 5,    -- seconds to load the map before round starts
	RoundDuration        = 180,  -- maximum seconds a round can last
	EndScreenDuration    = 10,   -- seconds on the end screen before next intermission
	MinPlayers           = 2,    -- minimum players required to start a round
	Maps                 = {},   -- list of map names/identifiers to vote on
	Teams                = {},   -- list of team names e.g. {"Red", "Blue"}
	AutoBalance          = true, -- whether to auto-balance teams on assignment
}

-- simple signal implementation — no dependencies needed
local function newSignal()
	local signal = { _listeners = {} }

	function signal:connect(fn)
		table.insert(self._listeners, fn)
		return {
			disconnect = function()
				for i, listener in ipairs(self._listeners) do
					if listener == fn then
						table.remove(self._listeners, i)
						break
					end
				end
			end
		}
	end

	function signal:fire(...)
		for _, fn in ipairs(self._listeners) do
			task.spawn(fn, ...)
		end
	end

	return signal
end

--[[
	Cycle.new(config)

	Creates a new Cycle instance with the provided configuration.
	Merges with defaults so you only need to specify what you want to change.
--]]
function Cycle.new(config)
	config = config or {}

	local self = setmetatable({}, Cycle)

	-- merge config with defaults
	self.config = {}
	for k, v in pairs(DEFAULTS) do
		self.config[k] = config[k] ~= nil and config[k] or v
	end

	-- state
	self._state       = nil
	self._round       = 0
	self._currentMap  = nil
	self._votes       = {}   -- [player] = mapName
	self._teams       = {}   -- [teamName] = { player, ... }
	self._running     = false
	self._roundThread = nil

	-- public signals
	self.onStateChanged = newSignal()  -- fires (newState, oldState)
	self.onRoundStart   = newSignal()  -- fires (roundNumber, map)
	self.onRoundEnd     = newSignal()  -- fires (winner, roundNumber)
	self.onMapChosen    = newSignal()  -- fires (mapName)
	self.onTeamsAssigned = newSignal() -- fires (teamAssignments)
	self.onTimerTick    = newSignal()  -- fires (secondsRemaining) every second during round
	self.onVoteUpdate   = newSignal()  -- fires (voteTotals) when a vote is cast

	return self
end

-- internal: change state and fire signal
function Cycle:_setState(newState)
	local old = self._state
	self._state = newState
	self.onStateChanged:fire(newState, old)
end

-- internal: countdown that fires onTimerTick each second, returns early if interrupted
function Cycle:_countdown(duration)
	for i = duration, 1, -1 do
		if not self._running then return false end
		self.onTimerTick:fire(i)
		task.wait(1)
	end
	return true
end

-- internal: wait for minimum players, checking every 3 seconds
function Cycle:_waitForPlayers()
	while #Players:GetPlayers() < self.config.MinPlayers do
		if not self._running then return false end
		task.wait(3)
	end
	return true
end

--[[
	internal: run the map vote phase
	returns the winning map name
--]]
function Cycle:_runMapVote()
	self._votes = {}
	local maps = self.config.Maps

	-- if no maps configured, skip vote and return nil
	if not maps or #maps == 0 then
		return nil
	end

	self:_setState(STATES.MAP_VOTE)

	-- wait for votes to come in
	local elapsed = 0
	while elapsed < self.config.MapVoteDuration do
		if not self._running then return nil end
		task.wait(1)
		elapsed += 1
	end

	-- tally votes
	local totals = {}
	for _, map in ipairs(maps) do
		totals[map] = 0
	end
	for _, vote in pairs(self._votes) do
		if totals[vote] then
			totals[vote] += 1
		end
	end

	-- find winner — random tiebreak
	local winners = {}
	local highest = 0
	for map, count in pairs(totals) do
		if count > highest then
			highest = count
			winners = { map }
		elseif count == highest then
			table.insert(winners, map)
		end
	end

	-- if nobody voted, pick a random map
	if highest == 0 then
		return maps[math.random(1, #maps)]
	end

	local chosen = winners[math.random(1, #winners)]
	self.onMapChosen:fire(chosen)
	return chosen
end

--[[
	internal: assign players to teams
--]]
function Cycle:_assignTeams()
	local teamNames = self.config.Teams
	if not teamNames or #teamNames == 0 then return end

	local playerList = Players:GetPlayers()

	-- shuffle players for fair assignment
	for i = #playerList, 2, -1 do
		local j = math.random(1, i)
		playerList[i], playerList[j] = playerList[j], playerList[i]
	end

	-- reset team tables
	self._teams = {}
	for _, name in ipairs(teamNames) do
		self._teams[name] = {}
	end

	-- distribute evenly
	for i, player in ipairs(playerList) do
		local teamName = teamNames[((i - 1) % #teamNames) + 1]
		table.insert(self._teams[teamName], player)

		-- assign roblox Team object if it exists
		if self.config.AutoBalance then
			local teamObj = Teams:FindFirstChild(teamName)
			if teamObj and teamObj:IsA("Team") then
				player.Team = teamObj
			end
		end
	end

	self.onTeamsAssigned:fire(self._teams)
end

--[[
	Cycle:vote(player, mapName)

	Register a player's vote for a map during the MAP_VOTE state.
	Replaces their previous vote if they vote again.
--]]
function Cycle:vote(player, mapName)
	if self._state ~= STATES.MAP_VOTE then return end

	local maps = self.config.Maps
	local valid = false
	for _, m in ipairs(maps) do
		if m == mapName then valid = true; break end
	end

	if not valid then
		warn("[Cycle] Invalid map vote:", mapName)
		return
	end

	self._votes[player] = mapName

	-- compute and broadcast current totals
	local totals = {}
	for _, m in ipairs(maps) do totals[m] = 0 end
	for _, v in pairs(self._votes) do
		if totals[v] then totals[v] += 1 end
	end
	self.onVoteUpdate:fire(totals)
end

--[[
	Cycle:endRound(winner)

	Call this from your game logic when a win condition is met.
	winner can be a team name (string), a Player, or any value you want passed to onRoundEnd.
	If you don't call this, the round ends naturally when the timer runs out.
--]]
function Cycle:endRound(winner)
	if self._state ~= STATES.IN_ROUND then return end
	self._winner = winner

	-- cancel the round countdown by interrupting the thread
	if self._roundThread then
		task.cancel(self._roundThread)
		self._roundThread = nil
	end

	self:_finishRound(winner)
end

-- internal: transition to end screen
function Cycle:_finishRound(winner)
	self._round += 1
	self:_setState(STATES.END_SCREEN)
	self.onRoundEnd:fire(winner, self._round)
	task.wait(self.config.EndScreenDuration)
end

--[[
	internal: the main round loop
--]]
function Cycle:_loop()
	while self._running do
		-- intermission
		self:_setState(STATES.INTERMISSION)
		local ready = self:_waitForPlayers()
		if not ready then break end
		self:_countdown(self.config.IntermissionDuration)

		-- map vote
		local chosenMap = self:_runMapVote()
		self._currentMap = chosenMap

		-- loading
		self:_setState(STATES.LOADING)
		task.wait(self.config.LoadingDuration)

		-- round
		self:_setState(STATES.IN_ROUND)
		self:_assignTeams()
		self._winner = nil
		self.onRoundStart:fire(self._round + 1, self._currentMap)

		-- run countdown on its own thread so endRound() can cancel it
		local roundFinished = false
		self._roundThread = task.spawn(function()
			self:_countdown(self.config.RoundDuration)
			roundFinished = true
		end)

		-- wait until round thread finishes or is cancelled by endRound()
		while self._roundThread ~= nil and not roundFinished do
			task.wait(0.5)
		end
		self._roundThread = nil

		-- if nobody called endRound, time ran out — no winner
		if self._state == STATES.IN_ROUND then
			self:_finishRound(nil)
		end
	end
end

--[[
	Cycle:start()

	Starts the round loop. Safe to call once.
--]]
function Cycle:start()
	if self._running then
		warn("[Cycle] Already running.")
		return
	end
	self._running = true
	task.spawn(function()
		self:_loop()
	end)
end

--[[
	Cycle:stop()

	Stops the loop after the current state finishes.
--]]
function Cycle:stop()
	self._running = false
	if self._roundThread then
		task.cancel(self._roundThread)
		self._roundThread = nil
	end
end

--[[
	Cycle:getState()

	Returns the current state string.
--]]
function Cycle:getState()
	return self._state
end

--[[
	Cycle:getTeams()

	Returns the current team assignments as a table: { teamName = { player, ... } }
--]]
function Cycle:getTeams()
	return self._teams
end

--[[
	Cycle:getCurrentMap()

	Returns the name of the map currently in use.
--]]
function Cycle:getCurrentMap()
	return self._currentMap
end

return Cycle
