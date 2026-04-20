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
