"""Telemetry system for the Moria8 AI agent.

Provides a non-blocking UDP sender to transmit real-time game state,
agent policy/value estimates, and rewards to a separate dashboard process.
"""

from __future__ import annotations

import json
import socket
import logging
from dataclasses import dataclass, asdict, field
from typing import Any

logger = logging.getLogger(__name__)

# Default UDP port for telemetry
DEFAULT_TELEMETRY_PORT = 5555
DEFAULT_TELEMETRY_HOST = "127.0.0.1"

@dataclass
class TelemetryPacket:
    """A single telemetry update packet."""
    type: str  # 'turn_update', 'event', 'brain_update'
    timestamp: float
    data: dict[str, Any] = field(default_factory=dict)

class TelemetrySender:
    """Non-blocking UDP sender for AI telemetry.
    
    Uses UDP 'fire and forget' to ensure the training loop is not 
    bottlenecked by visualization or network latency.
    """
    
    def __init__(self, host: str = DEFAULT_TELEMETRY_HOST, port: int = DEFAULT_TELEMETRY_PORT):
        self.host = host
        self.port = port
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        logger.info("Telemetry sender initialized for %s:%d", host, port)

    def send(self, packet_type: str, data: dict[str, Any]) -> None:
        """Send a telemetry packet via UDP."""
        import time
        packet = TelemetryPacket(
            type=packet_type,
            timestamp=time.time(),
            data=data
        )
        
        try:
            message = json.dumps(asdict(packet)).encode('utf-8')
            self._sock.sendto(message, (self.host, self.port))
        except (OSError, TypeError) as e:
            # UDP send failures are ignored to avoid crashing the trainer
            logger.debug("Failed to send telemetry packet: %s", e)

    def send_turn_update(self, 
                         turn: int, 
                         pos: tuple[int, int], 
                         hp: tuple[int, int],
                         depth: int,
                         action: str | None = None,
                         reward: float = 0.0,
                         messages: list[str] | None = None) -> None:
        """Convenience method for standard per-turn updates."""
        self.send("turn_update", {
            "turn": turn,
            "pos": pos,
            "hp": hp,
            "depth": depth,
            "action": action,
            "reward": reward,
            "messages": messages or []
        })

    def send_brain_update(self, 
                          value_estimate: float, 
                          policy_probs: list[float] | None = None) -> None:
        """Send AI internal state (value function and policy)."""
        self.send("brain_update", {
            "v": value_estimate,
            "p": policy_probs or []
        })

    def send_event(self, event_name: str, details: str = "") -> None:
        """Send a discrete game event (e.g., 'level_up', 'death', 'found_item')."""
        self.send("event", {
            "name": event_name,
            "details": details
        })

    def send_map_update(self, map_data: bytes) -> None:
        """Send the full 80x48 dungeon map (3840 bytes)."""
        # Convert bytes to list of ints for JSON serialization
        self.send("map_update", {
            "data": list(map_data)
        })

    def close(self) -> None:
        """Close the socket."""
        if self._sock:
            self._sock.close()
            self._sock = None
