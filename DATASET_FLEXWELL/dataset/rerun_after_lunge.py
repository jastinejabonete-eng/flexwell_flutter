"""Placeholder runner: after extraction+export, re-runs the algorithm
comparison, cost measurement, and regenerates the figures with the new
Lunge feature vector. Run only after extract_features.py + export_for_app.py
have completed."""
import subprocess, sys
PY = sys.executable
for script in ["algo_comparison.py", "measure_cost.py", "make_figures.py"]:
    print(f"\n>>> running {script}")
    r = subprocess.run([PY, script], capture_output=True, text=True)
    print(r.stdout[-1500:])
    if r.returncode != 0:
        print("FAILED:", script, r.stderr[-800:])
        sys.exit(1)
print("\nALL DONE")
