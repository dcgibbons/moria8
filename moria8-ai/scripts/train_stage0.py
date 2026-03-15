"""Training script for Stage 0: Maze Navigation.

Uses Stable Baselines 3 (PPO) to train the agent to explore
the dungeon and find the stairs.
"""

import logging
import sys
from pathlib import Path

# Add parent dir to path so we can import moria_ai
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import BaseCallback
from stable_baselines3.common.env_checker import check_env

from moria_ai.game_interface import GameInterface
from moria_ai.moria_env import MoriaEnv
from moria_ai.telemetry import TelemetrySender

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s: %(message)s")
logger = logging.getLogger("train")

class TelemetryCallback(BaseCallback):
    """Callback to send training metrics to the dashboard."""
    def __init__(self, env: MoriaEnv, verbose=0):
        super().__init__(verbose)
        self.moria_env = env

    def _on_step(self) -> bool:
        # Extract value estimate from PPO (if available)
        try:
            # We approximate the value estimate from the rollout buffer
            v = self.model.rollout_buffer.values[self.model.rollout_buffer.pos - 1][0]
            
            # Note: We can't easily extract per-action policy probabilities mid-step
            # without running another forward pass, so we just send the value.
            if self.moria_env.telemetry:
                self.moria_env.telemetry.send_brain_update(v=float(v))
        except Exception:
            pass
        return True

def main():
    symbol_file = Path("commodore/c64/out/main.vs")
    if not symbol_file.exists():
        logger.error(f"Symbol file not found: {symbol_file}")
        sys.exit(1)

    logger.info("Initializing Game Interface...")
    gi = GameInterface(symbol_file=symbol_file)
    
    logger.info("Initializing Telemetry...")
    telemetry = TelemetrySender()

    logger.info("Creating Environment...")
    # Max turns per episode (1000 is enough for a deep dive on one level)
    env = MoriaEnv(gi, telemetry=telemetry, max_turns=1000)

    # Optional: Verify the environment conforms to the Gym API
    # check_env(env)

    logger.info("Initializing PPO Model...")
    # PPO (Proximal Policy Optimization) is a good default for discrete action spaces
    # We use a relatively small neural net (pi=[64, 64], vf=[64, 64]) for fast iterations
    policy_kwargs = dict(net_arch=dict(pi=[64, 64], vf=[64, 64]))
    
    model = PPO("MultiInputPolicy", 
                env, 
                verbose=1,
                learning_rate=3e-4,
                n_steps=512, # Update every 512 steps
                batch_size=64,
                n_epochs=10,
                policy_kwargs=policy_kwargs,
                tensorboard_log="./moria8-ai/logs/ppo_stage0/")

    logger.info("Starting Training (Stage 0: Maze Navigation)...")
    logger.info("Make sure VICE is running, character is created, and dashboard is open.")
    
    # Connect to VICE (reset() will do this, but doing it here is cleaner)
    env.reset()

    callback = TelemetryCallback(env)

    try:
        # Train for 50,000 timesteps as an initial test run
        model.learn(total_timesteps=50000, callback=callback, progress_bar=True)
        
        logger.info("Training complete. Saving model...")
        model.save("moria8-ai/checkpoints/stage0_maze_nav")
        
    except KeyboardInterrupt:
        logger.info("Training interrupted. Saving checkpoint...")
        model.save("moria8-ai/checkpoints/stage0_maze_nav_interrupted")
    finally:
        gi.disconnect()

if __name__ == "__main__":
    main()
