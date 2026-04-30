import asyncio

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
            "username": username,
            "status": "ok"
        })

        #Broadcast updated lobby to all players
        if client_type == "phone":
            await game.broadcast_lobby()

        while True:
            # Wait for JSON data from the phone/puck
            data = await websocket.receive_json()
            msg_type = data.get("type")
            
            if msg_type == "start_game":
                success = await game.start_game()
                if not success:
                    await websocket.send_json({
                        "type": "error",
                        "message": "Error in starting game - are there at least 3 players?"
                    })

            # Phone taps puck
            elif client_type == "phone" and data.get("type") == "nfc_tap":
                target_puck = data.get("puck_id")
                await game.handle_tap(client_id, target_puck, datetime.now())
                print(f"Phone {client_id} tapped Puck {target_puck}")
                
                # # Tell puck to change color
                # await manager.send_to_puck(target_puck, {"action": "change_color", "color": "green"})
            elif client_type == "phone" and data.get("type") == "infect":
                infected_id = data.get("target_id")
                print(f"{infected_id} infected")
                asyncio.create_task(game.handle_infection(client_id, infected_id, datetime.now()))
            
            if game.check_game_over():
                game.end_game()
                break

    except WebSocketDisconnect:
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

if __name__ == "__main__":
    import uvicorn
    # Use 0.0.0.0 to make it accessible to your phone/ESP32 on the same Wi-Fi
    uvicorn.run(app, host="0.0.0.0", port=8000)