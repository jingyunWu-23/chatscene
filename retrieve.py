import runpy
import sys
from pathlib import Path


if __name__ == "__main__":
    repo_root = Path(__file__).resolve().parent
    retrieve_dir = repo_root / "retrieve"
    sys.path.insert(0, str(retrieve_dir))
    runpy.run_path(str(retrieve_dir / "retrieve.py"), run_name="__main__")
