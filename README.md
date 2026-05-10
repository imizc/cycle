# Cycle

A round management library for Roblox. Cycle handles the full loop - intermission, map voting, team assignment, round timing, and win conditions - so your game logic only has to care about what makes your game unique.

Built to be generic. Works for any game.

---

## Getting Started

Place `src/Cycle.lua` in `ServerScriptService`, then create a round system in a server Script:

```lua
local Cycle = require(game.ServerScriptService.Cycle)

local round = Cycle.new({
	Maps  = { "Warehouse", "Rooftop", "Desert" },
	Teams = { "Red", "Blue" },
})

round:start()
```

---

## How it works

Cycle runs a continuous loop through five states:

```
Intermission -> MapVote -> Loading -> InRound -> EndScreen -> repeat
```

Each state fires `onStateChanged` so you can react - update UI, load maps, unlock gameplay, show results. Cycle manages the timing. You manage the game.

---

## Configuration

Pass a config table to `Cycle.new()`. All fields are optional.

| Key | Default | Description |
|---|---|---|
| `IntermissionDuration` | `20` | Seconds in the lobby before voting |
| `MapVoteDuration` | `15` | Seconds the vote stays open |
| `LoadingDuration` | `5` | Seconds to load the map before round start |
| `RoundDuration` | `180` | Max seconds a round can last |
| `EndScreenDuration` | `10` | Seconds on the results screen |
| `MinPlayers` | `2` | Minimum players required to start |
| `Maps` | `{}` | List of map names to vote on |
| `Teams` | `{}` | List of team names to assign players to |
| `AutoBalance` | `true` | Assign Roblox Team objects automatically |

---

## Reacting to state changes

```lua
round.onStateChanged:connect(function(newState, oldState)
	if newState == Cycle.States.LOADING then
		local map = round:getCurrentMap()
		-- load your map here
	elseif newState == Cycle.States.IN_ROUND then
		-- unlock gameplay
	end
end)
```

Available states via `Cycle.States`:

| Constant | Value |
|---|---|
| `Cycle.States.INTERMISSION` | `"Intermission"` |
| `Cycle.States.MAP_VOTE` | `"MapVote"` |
| `Cycle.States.LOADING` | `"Loading"` |
| `Cycle.States.IN_ROUND` | `"InRound"` |
| `Cycle.States.END_SCREEN` | `"EndScreen"` |

---

## Signals

All signals follow the same pattern: `signal:connect(fn)` returns a connection with a `:disconnect()` method.

**`onStateChanged(newState, oldState)`**
Fires whenever the round state changes.

**`onRoundStart(roundNumber, mapName)`**
Fires at the beginning of `InRound`, after teams are assigned.

**`onRoundEnd(winner, roundNumber)`**
Fires when the round ends. `winner` is whatever you passed to `endRound()`, or `nil` if the timer ran out.

**`onMapChosen(mapName)`**
Fires at the end of voting with the winning map.

**`onTeamsAssigned(teams)`**
Fires at round start. `teams` is a table of `{ teamName = { player, ... } }`.

**`onTimerTick(secondsRemaining)`**
Fires every second during `InRound`. Use this to sync a timer UI to clients.

**`onVoteUpdate(totals)`**
Fires when a vote is cast. `totals` is a table of `{ mapName = voteCount }`.

---

## API

**`Cycle.new(config?)`**
Creates a new round system instance.

**`round:start()`**
Starts the round loop.

**`round:stop()`**
Stops the loop after the current state.

**`round:vote(player, mapName)`**
Registers a player's map vote. Only counts during `MapVote` state.

**`round:endRound(winner)`**
Ends the round early with a winner. Pass a team name, a Player, or any value. Pass `nil` for a draw. Does nothing if not in `InRound`.

**`round:getState()`**
Returns the current state string.

**`round:getTeams()`**
Returns the current team assignments.

**`round:getCurrentMap()`**
Returns the name of the active map.

---

## License

MIT. Use it however you want.

Built by [isaac](https://github.com/imizc).
