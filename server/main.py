import asyncio
from sys import exception

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse, HTMLResponse
from connection_manager import ConnectionManager
from game_manager import GameManager
from datetime import datetime

app = FastAPI()

manager = ConnectionManager()
game = GameManager(manager)

@app.websocket("/ws/{client_type}/{client_id}")
async def websocket_endpoint(websocket: WebSocket, client_type: str, client_id: str):
    await manager.connect(websocket, client_type, client_id)
    try:
        identity = await websocket.receive_json()
        
        # Check if player is reconnecting (if so, the identify json will be start_game. 
        # need to catch that so weirdness doesn't happen by calling start_game midgame)
        if client_id in game.inactivePlayers and game.inactivePlayers[client_id] is not None:
            game.reconnect_player(client_id)
            print(f"Player {client_id} reconnected and state restored")
        # If not reconnecting, phone must send identify message with username to join lobby
        else:
            if identity.get("type") != "identify":
                await websocket.close(code=1008, reason="First message must be identify")
                return

            # client_id = identity.get("player_id")
            username = identity.get("username", client_id)

            if client_type == "phone":
                game.add_player(player_id=client_id, username=username)

        # Send ack
        await websocket.send_json({
            "type": "connection_ack",
            "player_id": client_id,
            "username": game.player_id_to_username(client_id),
            "status": "ok"
        })

        if client_type == "phone":
            await game.broadcast_lobby()
        elif client_type == "puck":
            color = game.get_puck_color(client_id)
            if color:
                await manager.send_to_puck(client_id, {"action": "change_color", "color": color})

        while True:
            # Wait for JSON data from the phone/puck
            data = await websocket.receive_json()
            msg_type = data.get("type")
            
            if msg_type == "ping":
                await websocket.send_json({"type": "pong", "ts": data.get("ts")})
                continue

            if msg_type == "start_game" and game.state == "lobby":
                success = await game.start_game()
                if not success:
                    await websocket.send_json({
                        "type": "error",
                        "message": "Error in starting game - are there at least 3 players?"
                    })

            elif game.state == "voting":
                if msg_type == "imposter_reveal":
                    await game.reveal_imposter()
                continue # ignore all other messages during voting
            elif game.state == "imposter_revealed":
                if msg_type == "end_game":
                    await game.end_game()
            # Phone taps puck
            elif client_type == "phone" and data.get("type") == "nfc_tap":
                target_puck = data.get("puck_id")
                await game.handle_tap(client_id, target_puck, datetime.now())
                await manager.send_to_puck(f"puck_{target_puck}", {"action": "flash"})
                print(f"Phone {client_id} tapped Puck {target_puck}")
                
            elif client_type == "phone" and data.get("type") == "infect":
                infected_id = data.get("target_id")
                print(f"Attempting to infect player {infected_id}")
                asyncio.create_task(game.handle_infection(client_id, infected_id, datetime.now()))

            # Don't need to check if all infected in core game loop since we check after every infection

            # Don't need to check if all tasks completed in core game loop since we check after every task completion
               
            

    except Exception as e:
        print(f"Error with client {client_id}: {e}")
    finally:
        manager.disconnect(client_type, client_id)
        if client_type == "phone":
            game.remove_player(client_id)
            await game.broadcast_lobby()
        print(f"Client {client_id} disconnected")
        

# ONLY IF WE ARE USING CUSTOM URL SCHEME
# @app.get("/.well-known/apple-app-site-association")
# async def aasa():
#     return JSONResponse({
#         "applinks": {
#             "details": [
#                 {
#                     "appIDs": ["bellesee.game"],
#                     "components": [
#                         { "/": "/scan*" }
#                     ]
#                 }
#             ]
#         }
#     })

# @app.get("/scan")
# async def scan_fallback():
#     # shown in Safari if app isn't installed
#     return HTMLResponse("<h1>Open this link on your phone with the app installed.</h1>")

@app.get("/puck/{puck_id}/color/{color}")
async def set_puck_color(puck_id: str, color: str):
    await manager.send_to_puck(puck_id, {"action": "change_color", "color": color})
    return {"puck": puck_id, "color": color}

if __name__ == "__main__":
    import uvicorn
    # Use 0.0.0.0 to make it accessible to your phone/ESP32 on the same Wi-Fi
    uvicorn.run(app, host="0.0.0.0", port=8000)