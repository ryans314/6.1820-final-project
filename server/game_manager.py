
from dataclasses import dataclass, field
import random

@dataclass
class Player:
    player_id: str
    username: str
    is_imposter: bool = False
    status: str = "alive"  # "alive", "ghost", etc.
    completed_tasks: list[str] = field(default_factory=list)
    current_task: str = None

    def complete_task(self, task_id: str):
        if task_id not in self.completed_tasks:
            self.completed_tasks.append(task_id)
            self.current_task = None

class GameManager:
    def __init__(self, connection_manager):
        self.connection_manager = connection_manager
        self.players: dict[str, Player] = {}
        self.state: str = "lobby"  # "lobby", "in_progress", "ended"
        self.tap_sequence: list[str, str] = []  # List of (phone_id, puck_id) tuples

    def add_player(self, player_id: str, username: str):
        # Create the object and store it by ID
        self.players[player_id] = Player(player_id=player_id, username=username)

    def remove_player(self, player_id: str):
        self.players.pop(player_id, None)
    
    async def broadcast_lobby(self):
        """Send list of players to all connected phones"""
        await self.connection_manager.broadcast_to_phones({
            "type": "player_list",
            "players": self.get_player_list()
        })

    def get_player_list(self) -> list[dict]:
        """Return a list of players for broadcasting"""
        return [
            {"player_id": p.player_id, "username": p.username}
            for p in self.players.values()
        ]
    
    async def start_game(self):
        if len(self.players) < 3:
            print("Not enough players!")
            return
        
        # Assign imposter
        imposter_id = random.choice(list(self.players.keys()))
        self.players[imposter_id].is_imposter = True

        self.state = "in_progress"

        # Send players their roles
        for player_id, player in self.players.items():
            await self.connection_manager.send_to_phone(player_id, {
                "type": "game_start",
                "is_imposter": player.is_imposter,
                "players": self.get_player_list()
            })

        #assign tasks to non-imposters
        self.assign_tasks()
        
        

    def assign_tasks(self) -> None:
        pass

    def handle_tap(self, phone_id: str, puck_id: str) -> None:
        pass        

    def check_task_completion(self):
        pass

    def check_game_over(self) -> bool:
        pass

    def end_game(self) -> None:
        pass