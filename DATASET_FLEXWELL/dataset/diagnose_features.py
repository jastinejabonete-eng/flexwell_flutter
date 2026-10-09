"""
diagnose_features.py

Ground-truth check of the train/serve feature pipeline. Runs MediaPipe on ONE
clip of each exercise and prints the per-frame feature trajectory, so we can see
whether the training features are anatomically real (e.g. a squat knee angle
sweeping 180 -> ~90 -> 180) or corrupted (e.g. stuck at impossible values).

This does NOT modify anything; it only prints measurements so we can decide the
correct fix instead of guessing.
"""
import os, math
import cv2
import mediapipe as mp

mp_pose = mp.solutions.pose
DATASET = os.path.dirname(os.path.abspath(__file__))

L_SHOULDER, R_SHOULDER = 11, 12
L_ELBOW, R_ELBOW = 13, 14
L_WRIST, R_WRIST = 15, 16
L_HIP, R_HIP = 23, 24
L_KNEE, R_KNEE = 25, 26
L_ANKLE, R_ANKLE = 27, 28


class P:
    __slots__ = ("x", "y")
    def __init__(self, x, y): self.x, self.y = x, y


def to_pixels(landmarks, w, h):
    return [P(l.x * w, l.y * h) for l in landmarks]


def angle(a, b, c):
    r = math.atan2(c.y - b.y, c.x - b.x) - math.atan2(a.y - b.y, a.x - b.x)
    ang = abs(math.degrees(r))
    return 360 - ang if ang > 180 else ang


def midpoint(a, b):
    return P((a.x + b.x) / 2, (a.y + b.y) / 2)


def trajectory(path):
    cap = cv2.VideoCapture(path)
    meta = int(cap.get(cv2.CAP_PROP_ORIENTATION_META) or 0)
    auto_ok = bool(cap.set(cv2.CAP_PROP_ORIENTATION_AUTO, 1))
    rc = {90: cv2.ROTATE_90_CLOCKWISE, 180: cv2.ROTATE_180,
          270: cv2.ROTATE_90_COUNTERCLOCKWISE}.get(meta) if meta in (90,180,270) and not auto_ok else None
    feat = []
    with mp_pose.Pose(static_image_mode=False) as pose:
        while cap.isOpened():
            ok, frame = cap.read()
            if not ok: break
            if rc is not None: frame = cv2.rotate(frame, rc)
            res = pose.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
            if not res.pose_landmarks: continue
            lm = to_pixels(res.pose_landmarks.landmark, frame.shape[1], frame.shape[0])
            feat.append({
                "knee": angle(lm[L_HIP], lm[L_KNEE], lm[L_ANKLE]),
                "elbow": angle(lm[L_SHOULDER], lm[L_ELBOW], lm[L_WRIST]),
                "bodyline": angle(lm[L_SHOULDER], lm[L_HIP], lm[L_ANKLE]),
                "hip_y": lm[L_HIP].y, "shoulder_y": lm[L_SHOULDER].y,
            })
    cap.release()
    return feat


def summarize(name, feat, key):
    vals = [f[key] for f in feat]
    if not vals:
        print(f"  {name}: no landmarks"); return
    print(f"  {name}: n={len(vals)} {key}: min={min(vals):.1f} max={max(vals):.1f} "
          f"mean={sum(vals)/len(vals):.1f}  first={vals[0]:.1f} last={vals[-1]:.1f}")


def first_clip(exercise, label):
    d = os.path.join(DATASET, exercise, label)
    if not os.path.isdir(d): return None
    for f in sorted(os.listdir(d)):
        if f.lower().endswith((".mp4", ".mov", ".avi")):
            return os.path.join(d, f)
    return None


print("=== SQUAT (expect knee angle 180 -> ~90 -> 180 through a rep) ===")
for lbl in ("correct", "incorrect"):
    c = first_clip("Squat", lbl)
    if c:
        f = trajectory(c)
        summarize(os.path.basename(c), f, "knee")
        # show a down-sampled trace of knee angle across the clip
        knee = [round(x["knee"]) for x in f]
        print("    knee trace (every 8th frame):", knee[::8])

print("\n=== PUSH-UP (expect elbow angle 170 -> ~70 -> 170 through a rep) ===")
for lbl in ("correct", "incorrect"):
    c = first_clip("Push-Up", lbl)
    if c:
        f = trajectory(c)
        summarize(os.path.basename(c), f, "elbow")
        el = [round(x["elbow"]) for x in f]
        print("    elbow trace (every 8th frame):", el[::8])

print("\n=== PLANK (expect body line ~165-180 held) ===")
c = first_clip("Plank", "correct")
if c:
    f = trajectory(c)
    summarize(os.path.basename(c), f, "bodyline")

print("\n=== LUNGE (expect front knee angle sweeping) ===")
for lbl in ("correct", "incorrect"):
    c = first_clip("Lunge", lbl)
    if c:
        f = trajectory(c)
        summarize(os.path.basename(c), f, "knee")
