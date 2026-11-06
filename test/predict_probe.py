"""Probe the trained FlexWell KNN models from a Dart-side simulation test.

For each (exercise, feature-vector) probe, computes the k=5 vote in z-score
space against assets/knn_training_data.json and reports the verdict, the
nearest-neighbour z-distance, and whether it would be flagged OOD.
"""
import json
import math
import sys

HERE = r"C:\Users\Janelyn\Downloads\Flutter\Flexwell\flexwell_flutter"
m = json.load(open(rf"{HERE}\assets\knn_training_data.json", encoding="utf-8"))


def vote(ex_name, probe, k=5):
    d = m[ex_name]
    mean, std, exs = d["mean"], d["std"], d["examples"]
    z = [(f - mean[i]) / std[i] for i, f in enumerate(probe)]
    dists = []
    for e in exs:
        ez = [(f - mean[i]) / std[i] for i, f in enumerate(e["features"])]
        dists.append((math.dist(z, ez), e["label"]))
    dists.sort()
    kn = dists[:k]
    nbad = sum(1 for _, label in kn if label != "correct")
    verdict = "incorrect" if nbad > len(kn) // 2 else "correct"
    flags = []
    if dists[0][0] > d["oodRadius"]:
        flags.append("OOD!")
    return (
        f"{ex_name} probe {probe} -> kNN {nbad}/{len(kn)} bad -> {verdict}"
        f" | nearest-z {dists[0][0]:.2f} (ood {d['oodRadius']:.2f}) {' '.join(flags)}"
    )


PROBES = [
    ("Squat", [59, 35], "good peak (from Dart sim)"),
    ("Squat", [141, 11], "bad peak (from Dart sim)"),
    ("Push-Up", [69.5, 171], "good peak (from Dart sim)"),
    ("Push-Up", [98.8, 173.4], "bad bottom frames (from Dart sim)"),
    ("Push-Up", [60, 173], "ideal good push-up"),
    ("Push-Up", [64, 171], "sim good peak with 60deg elbow target"),
    ("Push-Up", [61, 173.3], "training good mean"),
    ("Plank", [177.4, 0.0108, 0.0595], "good plank (from Dart sim)"),
    ("Plank", [151.2, 0.0996, 0.0595], "sagging plank (from Dart sim)"),
    ("Plank", [170, 0.01, 0.05], "ideal good plank"),
    ("Side Plank", [177, 0.011, 0.0956], "good side plank (from Dart sim)"),
    ("Side Plank", [145, 0.15, 0.35], "sagging side plank (from Dart sim)"),
    ("Pull-Up", [-0.7, 72], "good pull top (geometry estimate)"),
    ("Pull-Up", [-0.85, 57], "good pull deeper (estimate)"),
    ("Pull-Up", [-0.3, 95], "partial pull (estimate)"),
    ("Lunge", [134, 8, 25, 2.0, 25], "good lunge bottom (estimate)"),
    ("Lunge", [134.8, 7.3, 22.6, 2.7, 22.6], "exact Dart sim bottom (good)"),
    ("Lunge", [160, 35, 5, 3.0, 5], "leaning/bad lunge (estimate)"),
    ("Lunge", [163.0, 25.2, 8.5, 2.9, 8.5], "exact Dart sim bottom (bad)"),
]

if __name__ == "__main__":
    for ex, probe, note in PROBES:
        print(vote(ex, probe), "//", note)
