from fastapi import FastAPI, WebSocket, WebSocketDisconnect
import json
import asyncio

class ConnectionManager:
    def __init__(self):
        # Store connections in dictionaries for quick lookup
        self.active_phones: dict[str, WebSocket] = {}
        self.active_pucks: dict[str, WebSocket] = {}

    async def connect(self, websocket: WebSocket, client_type: str, client_id: str):
        await websocket.accept()
        if client_type == "phone":
            self.active_phones[client_id] = websocket
        else:
            self.active_pucks[client_id] = websocket
        print(f"Added {client_type}: {client_id}")

    def disconnect(self, client_type: str, client_id: str):
        if client_type == "phone":
            self.active_phones.pop(client_id, None)
        else:
            self.active_pucks.pop(client_id, None)

    async def send_to_puck(self, puck_id: str, message: dict):
        if puck_id in self.active_pucks:
            await self.active_pucks[puck_id].send_json(message)
    
    async def send_to_phone(self, player_ids: str | list[str], message: dict): 
        """
        Send message to all phones corresponding to all ids in player_ids
        """
        if isinstance(player_ids, str) and player_ids in self.active_phones:
            await self.active_phones[player_ids].send_json(message)
            return True
        
        verified_player_ids = [player_id for player_id in player_ids if player_id in self.active_phones]
        
        await asyncio.gather(
            *[self.active_phones[player_id].send_json(message) for player_id in verified_player_ids]
        )

        if len(verified_player_ids) != len(player_ids):
            print("WARNING: at least one player id is not an active player")
            return False
        return True
    
    async def broadcast_to_phones(self, message: dict): 
        await asyncio.gather(
            *[ws.send_json(message) for ws in self.active_phones.values()]
        )
