import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from moria_ai.vice_bridge import ViceBridge
b = ViceBridge()
b.connect(2.0)
print("Sending continue...")
b.continue_execution()
b.disconnect()
print("Done.")
