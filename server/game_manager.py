from __future__ import annotations
from dataclasses import dataclass, field
import random
from typing import Callable, Optional

@dataclass
class Interaction:
    player_id: str
    puck_id: int
    time: Optional[float] = None #0 = tap, else, expect an interaction every 0.5 seconds for length seconds

@dataclass
class Player:
    player_id: str
    username: str
    is_imposter: bool = False
    status: str = "alive"  # "alive", "ghost", etc.
    completed_tasks: list[Task] = field(default_factory=list)
    current_task: Task = None

    def complete_task(self, task_id: str):
        if task_id not in self.completed_tasks:
            self.completed_tasks.append(task_id)
            self.current_task = None
   
@dataclass
class Task:
    task_id: int
    task_type: str
    players: list[Player]
    expected_interactions: list[Interaction]
    order_matters: int
    status: int = 0 #0 = not done, 1 = done

    def update_status(self):
        self.status = int(all(done for _, done in self.expected_interactions))
    
    def check_new_interaction(self, interaction: Interaction):
        for i, (inter, done) in enumerate(self.expected_interactions):
            if not done:
                if interaction.player_id == inter.player_id and interaction.puck_id == inter.puck_id:
                    self.expected_interactions[i] = (inter, 1)
                    break
                if self.order_matters: #only check for first none completed task
                    break
        self.update_status()
     
class TapAll(Task):
    expected_no_players=3
    def __init__(self, players: list[Player], task_id: int):
        super().__init__(
            task_id=task_id,
            task_type="TapAll",
            status=0,
            players=players,
            expected_interactions=[
                (Interaction(players[0], 1), 0),
                (Interaction(players[1], 2), 0),
                (Interaction(players[2], 3), 0),
            ],
            order_matters=0,
        )
        
class TapOrder(Task):
    expected_no_players=2
    def __init__(self, players: list[Player], task_id: int):
        super().__init__(
            task_id=task_id,
            task_type="TapOrder",
            status=0,
            players=players,
            expected_interactions=[
                (Interaction(players[0], 1), 0),
                (Interaction(players[1], 2), 0),
                (Interaction(players[0], 1), 0),
                (Interaction(players[1], 2), 0),
            ],
            order_matters=1,
        )

class TapOne(Task):
    expected_no_players=1
    def __init__(self, players: list[Player], task_id: int):
        super().__init__(
            task_id=task_id,
            task_type="TapOne",
            status=0,
            players=players,
            expected_interactions=[
                (Interaction(players[0], 1), 0)],
            order_matters=0,
        )

taskTemplates = [TapOne, TapOrder, TapAll]

class GameManager:
    def __init__(self, connection_manager):
        self.connection_manager = connection_manager
        self.players: dict[str, Player] = {}
        self.state: str = "lobby"  # "lobby", "in_progress", "ended"
        self.tap_sequence: list[Interaction] = []  # List of (player_id, puck_id) tuples
        self.active_tasks: list[Task] = []
        self.round_num: int
        self.puck_colors: dict[int, str]

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
        await self.start_round()

    def assign_colors(self):
        colors = ["red", "blue", "purple", "green", "white", "brown", "yellow"]
        selected = random.sample(colors, 3)
        self.puck_colors = {1: selected[0], 2: selected[1], 3: selected[2]}
        #will need more code for communicating colors with pucks
            

    async def start_round(self) -> None:
        self.puck_colors = self.assign_colors()
        unassigned = list(self.players.values())
        task_id = 0

        # randomly assign tasks to players
        while unassigned:
            template = random.choice(taskTemplates)
            required = template.expected_no_players

            if len(unassigned) < required:
                template = TapOne
                required = 1

            assigned = random.sample(unassigned, required)
            task = template(players=assigned, task_id=task_id)
            task_id += 1

            for player in assigned:
                player.current_task = task
                await self.assign_task(player)
                unassigned.remove(player)

            self.active_tasks.append(task)

    async def assign_task(self, player):
        current_task = player.current_task
        other_players = None
        if current_task.expected_no_players > 1:
            other_players = [p.player_id for p in current_task.players if p.player_id != player.player_id]

        await self.connection_manager.send_to_phone(player.player_id, {
                "type": "task",
                "task_id": current_task.task_id,
                "task_type": current_task.task_type,
                "other_players": other_players
            })
        
    def handle_tap(self, player_id: str, puck_id: str, time: float) -> None:
        interact = Interaction(player_id=player_id, puck_id=puck_id, time=time)
        for t in self.active_tasks:
            t.check_new_interaction(interact)

    def check_task_completion(self):
        # loop through active tasks and see if status is now 1
        # if it is, move to completed for each player and remove from active tasks for both player and game
        pass

    def check_game_over(self) -> bool:
        pass

    def end_game(self) -> None:
        pass