
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

    async def start_game(self):
        if len(self.players) < 3:
            print("Not enough players!")
            return
        
        # Assign imposter
        imposter_id = random.choice(list(self.players.keys()))
        self.players[imposter_id].is_imposter = True

        self.state = "in_progress"

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