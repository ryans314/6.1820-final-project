# Server Functionality

The server will ultimately run on a RPi3/4, and will coordinate tasks, roles, and game state to players and pucks. 


## Capabilities:

So far, the server & client have the following capabilities:

- Players can choose their username
- Player ID is taken from their identifier for vendors (IDFV), which persists between sessions
- Players can join and leave a lobby
- Players can see other players in the lobby
- Players can start the game when at least 3 players have joined
- Upon starting the game, players will be assigned roles, with exactly 1 player being selected as the imposter

## Limitations

There are currently many limitations:

- Server- and client-side code both rely on hardcoded IP addresses
- Functionality only extends up to the start of the game
- There is only one lobby for all players, can't have multiple games or anything
- No concept of an owner/leader/admin or anything like that for a lobby, all players have equal privileges
- We don't check for repeat usernames
- No variation in the number of imposters assigned based on how many players there are

## Specs

The server uses webhooks via the FastAPI api

Clients connect to the websocket at the address `[ip_address]:8000/ws/{client_type}/{client_id}`, where client_type is either `phone` or `puck`, and client_id is their IDFV. 

The first message sent from the client to the server **must** be an identification message, in the following format:

```json
{
    "type": "identify",
    "player_id": "{client_id}",
    "username": "{username}"
}
```

Furthermore, all messages must have a `type` attribute which specifies the type of action being taken. 


# API
## From Server

### player_list
```json
{
"type": "player_list",
"players": {
    "player_id": "phone id established in initial connection", 
    "username":  "name given by player when joining"
    }
}
```

### new_task
- round_number should be limited to {"1", "2", "3"}
- target_pucks is an ordered list of len 2 lists, where the first element in target pucks represents the first player to tap and the color of the puck they need to tap, the 2nd element represents the 2nd player to tap and the color of the puck they need to tap, and so on.
```json
{
    "type": "new_task",
    "round": "{round_number} (string)",
    "task_id": "tracks each task assigned (int)",
    "task_type": "tracks the type of task",
    "task_description": "description to be given to players",
    "other_players": "lists other players if a multiplayer task, None otherwise",
    "target_pucks": [
        ["1st_player_username_to_tap", "1st_puck_color_to_tap"],
        ["2nd_player_username_to_tap", "2nd_puck_color_to_tap"]
    ]
}
```

### incorrect_puck
Sent when a player taps a puck that they did not need to
(whether it was the wrong puck or out of order with other players/pucks)
```json
{
    "type": "incorrect_puck"
}
```

### correct_puck
```json
{
    "type": "correct_puck"
}
```

### task_complete
```json
{
    "type": "task_complete"
}
```

### task_progress
Sent to players involved in a task whenever their task changes progress

```json
{
    "type": "task_progress",
    "task_id": "{task_id} (int)",
    "progress": "{task_progress} (float)"
}
```

### TODO: game_status
The game state must be one of: "lobby" "in_progress" "voting" or  "imposter_revealed"
```json
{
    "type": "game_status",
    "state": "{game_state}"
}
```

### infected
```json
{
    "type": "infected"
}
```

### TODO: imposter_revealed
```json
{
    "type": "imposter_revealed",
    "imposter": "{imposter_username}"
}
```

## From Phone
### start_game
```json
{
    "type": "start_game"
}
```

### nfc_tap
puckId should be constrained to {1, 2, 3}
```json
{
    "type": "nfc_tap",
    "puck_id": "{puckId} (String)"
}
```

### infect
only sent by imposter

```json
{
    "type": "infect",
    "target_id": "{player_id} of the target"
}
```
### TODO: imposter_reveal
sent after voting starts
```json
{
    "type": "imposter_reveal"
}
```