from pathlib import Path
import runpy
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[4] / "tools/multi_app"))
_namespace = runpy.run_path(str(Path(__file__).resolve().parents[4] / "tools/multi_app/pck.py"), run_name=__name__)
globals().update(_namespace)
