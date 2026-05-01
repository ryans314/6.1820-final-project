from __future__ import annotations
from connection_manager import ConnectionManager
from dataclasses import dataclass, field
import random
from typing import Callable, Optional
import asyncio

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
        assert task_id == self.current_task.task_id
        if task_id not in self.completed_tasks:
            self.completed_tasks.append(task_id)
            self.current_task = None
   
@dataclass
class Task:
    task_id: int
    task_type: str
    players: list[Player]
    expected_interactions: list[tuple[Interaction, bool]]
    order_matters: bool #TODO: order_matters allows interruptions, fix this
    is_completed: bool = False

    def update_completion_status(self) -> bool:
        """
        Update status to be 1 if completed (or 0 if not completed)

        Returns True if task is (newly) completed

        Generally should only be called on uncompleted or newly completed tasks
        """

        
        if self.is_completed:
            print("WARNING: update_completion_status called on completed Task")

        self.is_completed = int(all(done for _, done in self.expected_interactions))
        
        if self.is_completed:
            print("Task is completed!")
            return True
    
    def check_new_interaction(self, interaction: Interaction) -> bool:
        """
        Check if interaction is relevant to the task, and if it is update the task's interaction
        to mark the necessary interaction completed

        Returns True if the task is completed or False if not
        """
        print(f"checking task {self.task_id}")
        if self.is_completed:
            print("Task already completed")
            return
        if not self.player_in_task(interaction.player_id):
            print(f"Player {interaction.player_id} not in task {self.task_id}")
            return
        
        success = False
        for i, (inter, done) in enumerate(self.expected_interactions):
            expected_player_id = str(inter.player_id)
            given_player_id = str(interaction.player_id)
            expected_puck_id = int(inter.puck_id)
            given_puck_id = int(interaction.puck_id)
            if not done:
                print(f"players match? {expected_player_id == given_player_id} ({expected_player_id}, {given_player_id}) | pucks match? {given_puck_id == expected_puck_id} ({given_puck_id}, {expected_puck_id})")
                if expected_player_id == given_player_id and expected_puck_id == given_puck_id:
                    self.expected_interactions[i] = (inter, True)
                    print("Updated task interaction")
                    success = True
                    break
                if self.order_matters: #only check for first none completed task
                    break
            
        #Reset progress for entire task if tapping wasn't a success and order matters (and player was in the task, checked earlier)
        if not success and self.order_matters:
            print(f"Player in task, but wrong action/order. Resetting progress on task {self.task_id}")
            self.reset_task_progress()
        return self.update_completion_status()
     
    def player_in_task(self, player_id: str) -> bool:
        return any(player.player_id == player_id for player in self.players)
    
    def reset_task_progress(self):
        for i in range(len(self.expected_interactions)):
            inter, _ = self.expected_interactions[i]
            self.expected_interactions[i] = (inter, False)
class TapAll(Task):
    """
    Task: 3 players must tap 3 different pucks
    """
    expected_no_players=3
    def __init__(self, players: list[Player], task_id: int):
        super().__init__(
            task_id=task_id,
            task_type="TapAll",
            players=players,
            expected_interactions=[
                (Interaction(players[0].player_id, 1), False),
                (Interaction(players[1].player_id, 2), False),
                (Interaction(players[2].player_id, 3), False),
            ],
            order_matters=0,
        )
        
class TapOrder(Task):
    """
    Two players must tap two separate pucks, alternating twice
    Example: P1 taps puck1, P2 taps puck2, P1 taps puck1, P2 taps puck2
    """
    expected_no_players=2
    def __init__(self, players: list[Player], task_id: int):
        super().__init__(
            task_id=task_id,
            task_type="TapOrder",
            players=players,
            expected_interactions=[
                (Interaction(players[0].player_id, 1), False),
                (Interaction(players[1].player_id, 2), False),
                (Interaction(players[0].player_id, 1), False),
                (Interaction(players[1].player_id, 2), False),
            ],
            order_matters=1,
        )

class TapOne(Task):
    """
    One player must tap a single puck
    """
    expected_no_players=1
    def __init__(self, players: list[Player], task_id: int):
        super().__init__(
            task_id=task_id,
            task_type="TapOne",
            players=players,
            expected_interactions=[
                (Interaction(players[0].player_id, 1), False)],
            order_matters=0,
        )

taskTemplates = [TapOne, TapOrder, TapAll]

class GameManager:
    def __init__(self, connection_manager):
        self.connection_manager: ConnectionManager  = connection_manager
        self.players: dict[str, Player] = {} #player_id : Player Object
        self.state: str = "lobby"  # "lobby", "in_progress", "ended"
        self.tap_sequence: list[Interaction] = []  # List of (player_id, puck_id) tuples
        self.active_tasks: list[Task] = []
        self.round_num: int = 1
        self.puck_colors: dict[int, str] = {}

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
    
    async def start_game(self) -> bool:
        """
        Starts the game. Returns True on success, False on failure
        """
        if len(self.players) < 3:
            print("Not enough players!")
            return False
        
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
        return True

    def get_puck_color(self, puck_id: str) -> str | None:
        """Return stored color for a puck given its string ID (e.g. 'puck_1')."""
        if not self.puck_colors:
            return None
        try:
            index = int(puck_id.split("_")[-1])
            return self.puck_colors.get(index)
        except (ValueError, AttributeError):
            return None

    def assign_colors(self) -> dict[int, str]:
        colors = ["red", "blue", "purple", "green", "white", "brown", "yellow"]
        selected = random.sample(colors, 3)
        return {1: selected[0], 2: selected[1], 3: selected[2]}

    async def start_round(self) -> None:
        self.puck_colors = self.assign_colors()
        for puck_id, color in self.puck_colors.items():
            await self.connection_manager.send_to_puck(f"puck_{puck_id}", {"action": "change_color", "color": color})
        unassigned = list(self.players.values())
        task_id = 0
        
        round_num = self.round_num
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
                await self.assign_task(player, round_num)
                unassigned.remove(player)

            self.active_tasks.append(task)
            self.round_num += 1

    
    async def start_voting(self) -> None:
        """
        After all tasks are completed, start voting
        """
        pass

    async def assign_task(self, player: Player, round_num: int) -> None:
        current_task = player.current_task
        other_players = None
        if current_task.expected_no_players > 1:
            other_players = [p.player_id for p in current_task.players if p.player_id != player.player_id]

        await self.connection_manager.send_to_phone(player.player_id, {
                "type": "new_task",
                "round": str(round_num),
                "task_id": current_task.task_id,
                "task_type": current_task.task_type,
                "other_players": other_players,
                "target_pucks": [ #ordered list of [player_username, puck_color]
                [self._player_id_to_username(inter.player_id), self.get_puck_color(f"puck_{inter.puck_id}")]
                      for inter, _ in current_task.expected_interactions
                ]
            })
        
    async def handle_tap(self, player_id: str, puck_id: str, time: float) -> None:
        """
        Handle tapping a puck:
        - update relevant interactions
        - mark tasks completed as necessary
        - notify phones if tap resulted in task completion
        - trigger end of round voting if n-1 tasks completed
        """
        interact = Interaction(player_id=player_id, puck_id=puck_id, time=time)
        for t in self.active_tasks:
            t.check_new_interaction(interact)
        
        # If a task was completed, check for end of round conditions
        if await self.check_task_completion():
            if len(self.active_tasks) == 1:
                print("End of Round!")
                await self.start_voting()
                #TODO: start voting


    async def check_task_completion(self):
        """
        Checks all current tasks for completion. Update game state to reflect completed tasks
        and notify any phones of task completion.

        Returns True if any tasks were completed
        """
        # loop through active tasks and see if is_completed
        # if it is, move to completed for each player and remove from active tasks for both player and game
        # use task_complete to let phone know as task is done
        # await self.connection_manager.send_to_phone(player_id, {
        #     "type": "task_complete"
        # })
        players_to_notify = []
        for task in self.active_tasks[:]:
            if task.is_completed:
                for player in task.players:
                    player.complete_task(task.task_id)
                    players_to_notify.append(player.player_id)
                self.active_tasks.remove(task)
        
        if players_to_notify:
            await self.connection_manager.send_to_phone(players_to_notify, {
                "type": "task_complete"
            })
            return True
        
        return False

    async def handle_infection(self, infector_id: str, infected_id: str, time: float) -> None:
        """
        Handle infection:
        - update infected player's status
        - notify phones of infection after a delay (10-20 seconds)
        """
        # Verify infector is imposter
        infector_player = self.players.get(infector_id)
        if not infector_player or not infector_player.is_imposter:
            print(f"Player {infector_id} is not an imposter or does not exist. Cannot infect.")
            return
        
        # Verify infected player is alive
        infected_player = self.players.get(infected_id)
        if not infected_player or infected_player.status != "alive":
            print(f"Player {infected_id} is not alive or does not exist. Cannot be infected.")
            return
        
        infected_player.status = "infected"
        delay = random.uniform(10,20)
        print(f"{infected_player.username} has been infected! Notifying in {delay:.2f} seconds...")
        
        await asyncio.sleep(delay)
        await self.connection_manager.send_to_phone(infected_id, {
            "type": "infected"
        })

        if self.check_game_over():
            self.end_game()
        

    def check_game_over(self) -> bool:
        if all(p.status != "alive" for p in self.players.values() if not p.is_imposter):
            print("All non-imposters have been infected. Imposter wins!")
            return True
        return False
    
    def end_game(self) -> None:
        pass

    def _player_id_to_username(self, player_id: str) -> str:
        player = self.players.get(player_id)
        return player.username if player else "Unknown"