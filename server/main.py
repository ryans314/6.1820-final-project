from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from connection_manager import ConnectionManager
from game_manager import GameManager

app = FastAPI()

manager = ConnectionManager()

@app.websocket("/ws/{client_type}/{client_id}")
async def websocket_endpoint(websocket: WebSocket, client_type: str, client_id: str):
    await manager.connect(websocket, client_type, client_id)
    try:
        while True:
            # Wait for JSON data from the phone/puck
            data = await websocket.receive_json()
            
            # Phone taps puck
            if client_type == "phone" and data.get("event") == "nfc_tap":
                target_puck = data.get("puck_id")
                print(f"Phone {client_id} tapped Puck {target_puck}")
                
                # Tell puck to change color
                await manager.send_to_puck(target_puck, {"action": "change_color", "color": "green"})

    except WebSocketDisconnect:
        manager.disconnect(client_type, client_id)
        print(f"Client {client_id} disconnected")

if __name__ == "__main__":
    import uvicorn
    # Use 0.0.0.0 to make it accessible to your phone/ESP32 on the same Wi-Fi
    uvicorn.run(app, host="0.0.0.0", port=8000)