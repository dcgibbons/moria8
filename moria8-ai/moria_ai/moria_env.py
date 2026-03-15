"""Gymnasium environment for Moria8 on the C64.

Wraps the GameInterface and provides a standard RL interface:
    reset()
    step(action)
    get_action_mask()

Implements Action Masking to prune illegal/useless moves.
"""

from __future__ import annotations

import logging
import numpy as np
import gymnasium as gym
from gymnasium import spaces
from typing import Any, SupportsFloat

from .game_interface import GameInterface, GameState
from .action_map import Action, SIMPLE_ACTIONS
from .memory_map import MAP_WIDTH, MAP_HEIGHT
from .telemetry import TelemetrySender

logger = logging.getLogger(__name__)

# Action delta mapping
ACTION_DELTAS = {
    Action.NORTH: (0, -1),
    Action.SOUTH: (0, 1),
    Action.WEST: (-1, 0),
    Action.EAST: (1, 0),
    Action.NORTHWEST: (-1, -1),
    Action.NORTHEAST: (1, -1),
    Action.SOUTHWEST: (-1, 1),
    Action.SOUTHEAST: (1, 1),
}

class MoriaEnv(gym.Env):
    """Gymnasium environment for Moria8.
    
    Attributes:
        gi: GameInterface instance.
        telemetry: Optional TelemetrySender.
        action_space: Discrete space (mapped to SIMPLE_ACTIONS for now).
        observation_space: Composite space with player/map/monster data.
    """
    
    def __init__(self, 
                 gi: GameInterface, 
                 telemetry: TelemetrySender | None = None,
                 max_turns: int = 1000):
        super().__init__()
        self.gi = gi
        self.telemetry = telemetry
        self.max_turns = max_turns
        self.turn_count = 0
        
        # Use simple action set for now
        self._actions = SIMPLE_ACTIONS
        self.action_space = spaces.Discrete(len(self._actions))
        
        # Observation space (vitals + local map)
        self.observation_space = spaces.Dict({
            "vitals": spaces.Box(low=0, high=65535, shape=(10,), dtype=np.uint16), # HP, XP, etc.
            "pos": spaces.Box(low=0, high=255, shape=(2,), dtype=np.uint8),       # (x, y)
            "map": spaces.Box(low=0, high=255, shape=(11, 11), dtype=np.uint8),    # 11x11 window
        })
        
        self._last_state: GameState | None = None
        self._map_data: bytes | None = None

    def reset(self, seed: int | None = None, options: dict[str, Any] | None = None) -> tuple[dict[str, Any], dict[str, Any]]:
        """Reset the environment (re-launches VICE or loads snapshot)."""
        super().reset(seed=seed)
        self.turn_count = 0
        
        # In a real training run, we'd use snapshots here.
        # For now, just ensure we're connected and waiting for input.
        if not self.gi.bridge._sock:
            self.gi.connect()
            self.gi.setup_breakpoints()
        
        self.gi.wait_for_input()
        self._last_state = self.gi.read_state()
        self._map_data = self.gi.read_map()
        
        # Send initial telemetry
        if self.telemetry:
            self.telemetry.send_map_update(self._map_data)
            self._send_telemetry(None, 0.0, ["Environment Reset"])

        return self._get_obs(), {}

    def step(self, action_idx: int) -> tuple[dict[str, Any], SupportsFloat, bool, bool, dict[str, Any]]:
        """Execute one game turn."""
        action = self._actions[action_idx]
        self.turn_count += 1
        
        # Step the game
        curr_state = self.gi.step(action)
        reward = self._compute_reward(self._last_state, curr_state)
        
        # Read messages for this turn
        messages = self.gi.read_messages()
        
        self._last_state = curr_state
        # Periodically refresh map data (e.g., every 5 turns)
        if self.turn_count % 5 == 0:
            self._map_data = self.gi.read_map()
            if self.telemetry:
                self.telemetry.send_map_update(self._map_data)
        
        # Send telemetry
        if self.telemetry:
            self._send_telemetry(action.name, reward, messages)
            
        terminated = curr_state.is_dead
        truncated = self.turn_count >= self.max_turns
        
        return self._get_obs(), reward, terminated, truncated, {}

    def get_action_mask(self) -> np.ndarray:
        """Returns a boolean array where True = action is allowed.
        
        Implements Action Masking based on map collisions and game rules.
        """
        mask = np.ones(self.action_space.n, dtype=bool)
        state = self._last_state
        m_data = self._map_data
        
        if not state or not m_data:
            return mask
            
        for i, action in enumerate(self._actions):
            # 1. Movement Masking (Walls/Closed Doors)
            if action in ACTION_DELTAS:
                dx, dy = ACTION_DELTAS[action]
                nx, ny = state.player_pos[0] + dx, state.player_pos[1] + dy
                
                if 0 <= nx < MAP_WIDTH and 0 <= ny < MAP_HEIGHT:
                    idx = ny * MAP_WIDTH + nx
                    tile_byte = m_data[idx]
                    t_type = (tile_byte >> 4) & 0x0F
                    
                    # Walls (0), closed doors (2), and rubble (4) are impassable
                    if t_type in [0, 2, 4]:
                        mask[i] = False
                else:
                    mask[i] = False # Out of bounds
            
            # 2. Stair Masking
            elif action == Action.GO_DOWN or action == Action.GO_UP:
                idx = state.player_pos[1] * MAP_WIDTH + state.player_pos[0]
                tile_byte = m_data[idx]
                t_type = (tile_byte >> 4) & 0x0F
                if t_type != 3: # STAIRS
                    mask[i] = False
            
            # 3. Consumption Masking
            elif action == Action.EAT or action == Action.QUAFF:
                # If we have zero items (approximate check for now)
                if state.item_count == 0:
                    mask[i] = False
                    
        return mask

    def _get_obs(self) -> dict[str, Any]:
        """Construct the observation dictionary."""
        s = self._last_state
        vitals = np.array([
            s.hp, s.max_hp, s.mp, s.max_mp,
            s.player_level, s.dungeon_level,
            s.ac, s.food, s.turn_count, s.hunger_state
        ], dtype=np.uint16)
        
        # Get 11x11 map window
        window = np.zeros((11, 11), dtype=np.uint8)
        px, py = s.player_pos
        for dy in range(-5, 6):
            for dx in range(-5, 6):
                nx, ny = px + dx, py + dy
                if 0 <= nx < MAP_WIDTH and 0 <= ny < MAP_HEIGHT:
                    idx = ny * MAP_WIDTH + nx
                    window[dy+5, dx+5] = self._map_data[idx]
                    
        return {
            "vitals": vitals,
            "pos": np.array(s.player_pos, dtype=np.uint8),
            "map": window
        }

    def _compute_reward(self, prev: GameState, curr: GameState) -> float:
        """Heuristic reward function (V2: Reward Shaping)."""
        reward = 0.0
        
        # HP Loss penalty
        if curr.hp < prev.hp:
            reward -= (prev.hp - curr.hp) * 0.5
            
        # Death penalty
        if curr.is_dead:
            reward -= 500.0
            
        # Exploration reward (if pos changed)
        if curr.player_pos != prev.player_pos:
            reward += 0.1
            
        # Depth reward
        if curr.dungeon_level > prev.dungeon_level:
            reward += 50.0
            
        return reward

    def _send_telemetry(self, action_name: str | None, reward: float, messages: list[str] | None = None):
        """Send data to the dashboard."""
        s = self._last_state
        self.telemetry.send_turn_update(
            turn=self.turn_count,
            pos=s.player_pos,
            hp=(s.hp, s.max_hp),
            depth=s.dungeon_level,
            action=action_name,
            reward=reward,
            messages=messages
        )
