"""Moria8 AI Dashboard.

A real-time Pygame-based visualization of the Moria8 AI agent.
Reconstructs the 80x48 dungeon map from telemetry and displays 
agent metrics (vitals, policy, value estimate).

Run this in a separate terminal:
    python moria_dashboard.py
"""

from __future__ import annotations

import json
import socket
import logging
import pygame
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# Add parent dir to path for imports
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from moria_ai.telemetry import DEFAULT_TELEMETRY_PORT, DEFAULT_TELEMETRY_HOST
from moria_ai.memory_map import MAP_WIDTH, MAP_HEIGHT

# Colors
COLOR_BG = (10, 10, 10)
COLOR_GRID = (30, 30, 30)
COLOR_WALL = (100, 100, 100)
COLOR_FLOOR = (40, 40, 40)
COLOR_DOOR = (139, 69, 19)
COLOR_STAIRS = (0, 255, 0)
COLOR_PLAYER = (50, 150, 255)
COLOR_MONSTER = (255, 50, 50)
COLOR_ITEM = (255, 255, 0)
COLOR_TEXT = (220, 220, 220)

TILE_SIZE = 12
MAP_PX_WIDTH = MAP_WIDTH * TILE_SIZE
MAP_PX_HEIGHT = MAP_HEIGHT * TILE_SIZE
SIDEBAR_WIDTH = 300
WINDOW_WIDTH = MAP_PX_WIDTH + SIDEBAR_WIDTH
WINDOW_HEIGHT = MAP_PX_HEIGHT

@dataclass
class DashboardState:
    """Current state of the dashboard visualization."""
    turn: int = 0
    player_pos: tuple[int, int] = (0, 0)
    hp: tuple[int, int] = (0, 0)
    depth: int = 0
    last_action: str = ""
    last_reward: float = 0.0
    value_estimate: float = 0.0
    policy_probs: list[float] = field(default_factory=list)
    map_data: list[int] | None = None  # 3840 bytes as list of ints
    monsters: list[dict[str, Any]] = field(default_factory=list)
    messages: list[str] = field(default_factory=list)

class TelemetryReceiver:
    """UDP receiver for telemetry packets."""
    def __init__(self, host: str = DEFAULT_TELEMETRY_HOST, port: int = DEFAULT_TELEMETRY_PORT):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind((host, port))
        self.sock.setblocking(False)
        print(f"Dashboard listening on {host}:{port}")

    def poll(self, state: DashboardState) -> bool:
        """Receive all pending packets and update state. Returns True if updated."""
        updated = False
        while True:
            try:
                data, _ = self.sock.recvfrom(65535)
                packet = json.loads(data.decode('utf-8'))
                self._update_state(state, packet)
                updated = True
            except (BlockingIOError, socket.error):
                break
            except Exception as e:
                print(f"Error parsing packet: {e}")
                break
        return updated

    def _update_state(self, state: DashboardState, packet: dict[str, Any]) -> None:
        p_type = packet.get("type")
        data = packet.get("data", {})
        
        if p_type == "turn_update":
            state.turn = data.get("turn", state.turn)
            state.player_pos = tuple(data.get("pos", state.player_pos))
            state.hp = tuple(data.get("hp", state.hp))
            state.depth = data.get("depth", state.depth)
            state.last_action = data.get("action", state.last_action)
            state.last_reward = data.get("reward", state.last_reward)
            
            # Update messages (keep a history of 10)
            new_msgs = data.get("messages", [])
            for m in new_msgs:
                if m not in state.messages[-2:]: # Avoid duplicates from re-reading same screen
                    state.messages.append(m)
            state.messages = state.messages[-10:]
        elif p_type == "brain_update":
            state.value_estimate = data.get("v", state.value_estimate)
            state.policy_probs = data.get("p", state.policy_probs)
        elif p_type == "map_update":
            state.map_data = data.get("data", state.map_data)

class MoriaDashboard:
    """Main dashboard application."""
    def __init__(self):
        pygame.init()
        # Explicitly init font if available
        try:
            pygame.font.init()
            self.font = pygame.font.SysFont("monospace", 16)
        except (NotImplementedError, ImportError, AttributeError) as e:
            print(f"Warning: Font module not available: {e}")
            self.font = None

        self.screen = pygame.display.set_mode((WINDOW_WIDTH, WINDOW_HEIGHT))
        pygame.display.set_caption("Moria8 AI Dashboard")
        self.clock = pygame.time.Clock()
        self.state = DashboardState()
        self.receiver = TelemetryReceiver()

    def run(self):
        running = True
        while running:
            # 1. Handle Events
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False

            # 2. Poll Telemetry
            self.receiver.poll(self.state)

            # 3. Draw
            self.screen.fill(COLOR_BG)
            self.draw_map()
            self.draw_sidebar()
            
            pygame.display.flip()
            self.clock.tick(30)

        pygame.quit()

    def draw_map(self):
        """Reconstruct the 80x48 dungeon map from telemetry."""
        if not self.state.map_data:
            # Draw placeholder grid if no map data yet
            for x in range(0, MAP_PX_WIDTH, TILE_SIZE * 5):
                pygame.draw.line(self.screen, COLOR_GRID, (x, 0), (x, MAP_PX_HEIGHT))
            for y in range(0, MAP_PX_HEIGHT, TILE_SIZE * 5):
                pygame.draw.line(self.screen, COLOR_GRID, (0, y), (MAP_PX_WIDTH, y))
            return

        # Draw map from data
        for i, tile_byte in enumerate(self.state.map_data):
            x = i % MAP_WIDTH
            y = i // MAP_WIDTH
            
            # Tile bitmask:
            # Bits 7-4: type (0=wall, 1=floor, 2=door, 3=stairs, 4=rubble, 5=magma, 6=quartz)
            # Bit 3: lit
            # Bit 2: visited/known
            t_type = (tile_byte >> 4) & 0x0F
            is_lit = (tile_byte >> 3) & 0x01
            is_visited = (tile_byte >> 2) & 0x01
            
            # If not visited, draw as black (or dim gray if we want to see it for debugging)
            if not is_visited:
                continue

            rect = (x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
            
            # Select color based on type
            if t_type == 0:  # WALL
                color = COLOR_WALL
            elif t_type == 1:  # FLOOR
                color = COLOR_FLOOR
            elif t_type == 2:  # DOOR
                color = COLOR_DOOR
            elif t_type == 3:  # STAIRS
                color = COLOR_STAIRS
            else:
                color = (50, 0, 50) # Unknown/Rubble/Magma

            # Dim if not lit
            if not is_lit:
                color = tuple(max(0, c - 30) for c in color)

            pygame.draw.rect(self.screen, color, rect)

        # Draw Player on top
        px, py = self.state.player_pos
        if 0 <= px < MAP_WIDTH and 0 <= py < MAP_HEIGHT:
            rect = (px * TILE_SIZE, py * TILE_SIZE, TILE_SIZE, TILE_SIZE)
            pygame.draw.rect(self.screen, COLOR_PLAYER, rect)
            pygame.draw.rect(self.screen, (255, 255, 255), rect, 1) # White border

    def draw_sidebar(self):
        if not self.font:
            return

        x_off = MAP_PX_WIDTH + 10
        y_off = 20
        
        lines = [
            f"TURN:   {self.state.turn}",
            f"DEPTH:  {self.state.depth}",
            f"POS:    {self.state.player_pos}",
            f"HP:     {self.state.hp[0]}/{self.state.hp[1]}",
            "",
            f"ACTION: {self.state.last_action}",
            f"REWARD: {self.state.last_reward:.4f}",
            f"VALUE:  {self.state.value_estimate:.4f}",
            "",
            "MESSAGES:"
        ]
        
        for line in lines:
            text = self.font.render(line, True, COLOR_TEXT)
            self.screen.blit(text, (x_off, y_off))
            y_off += 20
            
        # Draw messages with small indentation
        for msg in self.state.messages:
            text = self.font.render(f"> {msg}", True, (180, 180, 180))
            self.screen.blit(text, (x_off + 10, y_off))
            y_off += 18

if __name__ == "__main__":
    app = MoriaDashboard()
    app.run()
