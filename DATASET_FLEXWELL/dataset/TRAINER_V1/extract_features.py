"""
extract_features.py
Walks a folder of labeled videos and extracts a per-exercise feature vector
for training the FlexWell KNN classifier.
Each exercise now uses exactly the 2 features actually measurable from ITS
assigned camera placement (see the table above). Squat/Push-Up/Pull-Up use
a per-video CALIBRATION step (the first ~10 detected frames establish a
neutral baseline) since their depth signal is vertical displacement
relative to a starting position, not a fixed angle.
Output: features.csv with columns:
  exercise, label, feature_1, feature_2
"""
import os
import math
import cv2
import mediapipe as mp
import pandas as pd
mp_pose = mp.solutions.pose
DATASET_DIR = "dataset"
OUTPUT_CSV = "features.csv"
L_SHOULDER, R_SHOULDER = 11, 12
L_ELBOW, R_ELBOW = 13, 14
L_WRIST, R_WRIST = 15, 16
L_HIP, R_HIP = 23, 24
L_KNEE, R_KNEE = 25, 26
L_ANKLE, R_ANKLE = 27, 28
CALIBRATION_FRAMES = 10
SIDE_VIEW_EXERCISES = {"Lunge", "Plank", "Side Plank"}
FRONT_BACK_EXERCISES = {"Squat", "Push-Up", "Pull-Up"}
def calculate_angle(a, b, c):
    radians = math.atan2(c.y - b.y, c.x - b.x) - math.atan2(a.y - b.y, a.x - b.x)
    angle = abs(math.degrees(radians))
    if angle > 180:
        angle = 360 - angle
    return angle
def euclidean(a, b):
    return math.hypot(a.x - b.x, a.y - b.y)
def midpoint(a, b):
    class _Point:
        pass
    p = _Point()
    p.x = (a.x + b.x) / 2
    p.y = (a.y + b.y) / 2
    return p
def features_lunge(lm):
    hip, knee, ankle = lm[L_HIP], lm[L_KNEE], lm[L_ANKLE]
    shoulder = lm[L_SHOULDER]
    front_knee_angle = calculate_angle(hip, knee, ankle)
    dx = shoulder.x - hip.x
    dy = shoulder.y - hip.y
    torso_lean_angle = abs(math.degrees(math.atan2(dx, -dy)))
    return [front_knee_angle, torso_lean_angle]
def features_plank_style(lm):
    shoulder, hip, ankle = lm[L_SHOULDER], lm[L_HIP], lm[L_ANKLE]
    back_line_angle = calculate_angle(shoulder, hip, ankle)
    line_len = euclidean(shoulder, ankle)
    if line_len < 1e-6:
        hip_deviation_ratio = 0.0
    else:
        numerator = abs(
            (ankle.y - shoulder.y) * hip.x
            - (ankle.x - shoulder.x) * hip.y
            + ankle.x * shoulder.y
            - ankle.y * shoulder.x
        )
        hip_deviation_ratio = numerator / line_len / line_len
    return [back_line_angle, hip_deviation_ratio]
def torso_length(lm):
    shoulder_mid = midpoint(lm[L_SHOULDER], lm[R_SHOULDER])
    hip_mid = midpoint(lm[L_HIP], lm[R_HIP])
    return euclidean(shoulder_mid, hip_mid)
def raw_reference_point(exercise, lm):
    if exercise == "Squat":
        return midpoint(lm[L_HIP], lm[R_HIP])
    else:
        return midpoint(lm[L_SHOULDER], lm[R_SHOULDER])
def bonus_ratio(exercise, lm):
    if exercise == "Squat":
        knee_dist = euclidean(lm[L_KNEE], lm[R_KNEE])
        hip_dist = euclidean(lm[L_HIP], lm[R_HIP])
        return knee_dist / hip_dist if hip_dist > 1e-6 else 0.0
    else:
        elbow_dist = euclidean(lm[L_ELBOW], lm[R_ELBOW])
        shoulder_dist = euclidean(lm[L_SHOULDER], lm[R_SHOULDER])
        return elbow_dist / shoulder_dist if shoulder_dist > 1e-6 else 0.0
def process_video_front_back(path, exercise, label, pose):
    cap = cv2.VideoCapture(path)
    rows = []
    frame_skip = 5
    frame_idx = 0
    calibration_ys = []
    calibration_scales = []
    baseline_y = None
    baseline_scale = None
    while cap.isOpened():
        success, frame = cap.read()
        if not success:
            break
        frame_idx += 1
        image_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        result = pose.process(image_rgb)
        if not result.pose_landmarks:
            continue
        lm = result.pose_landmarks.landmark
        if baseline_y is None:
            ref = raw_reference_point(exercise, lm)
            scale = torso_length(lm)
            if scale > 1e-6:
                calibration_ys.append(ref.y)
                calibration_scales.append(scale)
            if len(calibration_ys) >= CALIBRATION_FRAMES:
                baseline_y = sum(calibration_ys) / len(calibration_ys)
                baseline_scale = sum(calibration_scales) / len(calibration_scales)
            continue
        if frame_idx % frame_skip != 0:
            continue
        ref = raw_reference_point(exercise, lm)
        scale = torso_length(lm)
        if scale < 1e-6 or baseline_scale < 1e-6:
            continue
        vertical_displacement = (ref.y - baseline_y) / baseline_scale
        ratio = bonus_ratio(exercise, lm)
        rows.append([exercise, label, vertical_displacement, ratio])
    cap.release()
    return rows
def process_video_side_view(path, exercise, label, pose):
    cap = cv2.VideoCapture(path)
    rows = []
    frame_skip = 5
    frame_idx = 0
    while cap.isOpened():
        success, frame = cap.read()
        if not success:
            break
        frame_idx += 1
        if frame_idx % frame_skip != 0:
            continue
        image_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        result = pose.process(image_rgb)
        if not result.pose_landmarks:
            continue
        lm = result.pose_landmarks.landmark
        if exercise == "Lunge":
            features = features_lunge(lm)
        else:
            features = features_plank_style(lm)
        rows.append([exercise, label] + features)
    cap.release()
    return rows
def main():
    all_rows = []
    with mp_pose.Pose(static_image_mode=False) as pose:
        for exercise in os.listdir(DATASET_DIR):
            exercise_path = os.path.join(DATASET_DIR, exercise)
            if not os.path.isdir(exercise_path):
                continue
            for label in ["correct", "incorrect"]:
                label_path = os.path.join(exercise_path, label)
                if not os.path.isdir(label_path):
                    continue
                for filename in os.listdir(label_path):
                    if not filename.lower().endswith((".mp4", ".mov", ".avi")):
                        continue
                    video_path = os.path.join(label_path, filename)
                    print(f"Processing {video_path} ...")
                    if exercise in FRONT_BACK_EXERCISES:
                        rows = process_video_front_back(video_path, exercise, label, pose)
                    elif exercise in SIDE_VIEW_EXERCISES:
                        rows = process_video_side_view(video_path, exercise, label, pose)
                    else:
                        print(f"  Skipping unrecognized exercise folder: {exercise}")
                        continue
                    all_rows.extend(rows)
    df = pd.DataFrame(all_rows, columns=["exercise", "label", "feature_1", "feature_2"])
    df.to_csv(OUTPUT_CSV, index=False)
    print(f"\nSaved {len(df)} labeled feature rows to {OUTPUT_CSV}")
    print(df.groupby(["exercise", "label"]).size())
if __name__ == "__main__":
    main()