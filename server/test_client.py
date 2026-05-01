import asyncio
import websockets
import json

clients = [
    {"client_type": "phone", "client_id": "device-001", "username": "Alice"},
    {"client_type": "phone", "client_id": "device-002", "username": "Bob"},
    {"client_type": "puck",  "client_id": "device-003", "username": "Charlie"},
]

async def run_client(client: dict, identified_event: asyncio.Event, all_identified: asyncio.Event):
    uri = f"wss://recollect-conjure-thesis.ngrok-free.dev/ws/{client['client_type']}/{client['client_id']}"
    
    try:
        async with websockets.connect(uri) as ws:
            await ws.send(json.dumps({
                "type": "identify",
                "player_id": client["client_id"],
                "username": client["username"],
            }))
            print(f"[{client['username']}] Connected and identified")
            identified_event.set()

            await all_identified.wait()

            # if client == clients[0]:
            #     await ws.send(json.dumps({"type": "start_game"}))
            #     print(f"[{client['username']}] Sent start_game")

            async for message in ws:
                try:
                    data = json.loads(message)
                    print(f"[{client['username']}] Received: {data}")
                except json.JSONDecodeError as e:
                    print(f"[{client['username']}] Bad JSON: {e}")

    except websockets.exceptions.ConnectionClosedError as e:
        print(f"[{client['username']}] Connection closed unexpectedly: {e}")
    except websockets.exceptions.ConnectionClosedOK:
        print(f"[{client['username']}] Connection closed cleanly")
    except Exception as e:
        print(f"[{client['username']}] Error: {e}")


async def main():
    events = [asyncio.Event() for _ in clients]
    all_identified = asyncio.Event()

    async def watch_all():
        await asyncio.gather(*[e.wait() for e in events])
        all_identified.set()

    await asyncio.gather(
        watch_all(),
        *[run_client(c, events[i], all_identified) for i, c in enumerate(clients)]
    )

if __name__ == "__main__":
    asyncio.run(main())
import asyncio
import websockets
import json

clients = [
    {"client_type": "phone", "client_id": "device-001", "username": "Alice"},
    {"client_type": "phone", "client_id": "device-002", "username": "Bob"},
    {"client_type": "phone", "client_id": "device-004", "username": "CCC"},
    {"client_type": "puck",  "client_id": "device-003", "username": "C"},
]

async def run_client(client: dict, identified_event: asyncio.Event, all_identified: asyncio.Event):
    uri = f"ws://localhost:8000/ws/{client['client_type']}/{client['client_id']}"
    
    try:
        async with websockets.connect(uri) as ws:
            await ws.send(json.dumps({
                "type": "identify",
                "player_id": client["client_id"],
                "username": client["username"],
            }))
            print(f"[{client['username']}] Connected and identified")
            identified_event.set()

            await all_identified.wait()

            # if client == clients[0]:
            #     await ws.send(json.dumps({"type": "start_game"}))
            #     print(f"[{client['username']}] Sent start_game")

            async for message in ws:
                try:
                    data = json.loads(message)
                    print(f"[{client['username']}] Received: {data}")
                except json.JSONDecodeError as e:
                    print(f"[{client['username']}] Bad JSON: {e}")

    except websockets.exceptions.ConnectionClosedError as e:
        print(f"[{client['username']}] Connection closed unexpectedly: {e}")
    except websockets.exceptions.ConnectionClosedOK:
        print(f"[{client['username']}] Connection closed cleanly")
    except Exception as e:
        print(f"[{client['username']}] Error: {e}")


async def main():
    events = [asyncio.Event() for _ in clients]
    all_identified = asyncio.Event()

    async def watch_all():
        await asyncio.gather(*[e.wait() for e in events])
        all_identified.set()

    await asyncio.gather(
        watch_all(),
        *[run_client(c, events[i], all_identified) for i, c in enumerate(clients)]
    )

if __name__ == "__main__":
    asyncio.run(main())
