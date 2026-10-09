# FlexWell

**A Mobile Application for Gym Exercise Posture Detection System**

FlexWell is an AI-driven, on-device fitness app that analyzes your exercise form in real time using your phone's camera. It detects body posture, classifies it as **Correct** or **Incorrect**, and gives instant visual feedback so you can train safely and effectively — no personal trainer required.

Built with **Flutter** and powered by **Google ML Kit Pose Detection** and a **K-Nearest Neighbors (KNN)** classifier running entirely on-device.

---

## ✨ Features

- 🎥 **Real-time posture detection** — live skeletal tracking with a colour-coded skeleton overlay (green = good form, red = adjust).
- 🧠 **On-device AI classification** — ML Kit extracts body landmarks; a KNN classifier judges form with no internet needed for analysis.
- 🏋️ **6 supported exercises** — Squat, Push-Up, Lunge, Pull-Up, Plank, and Side Plank.
- 🔁 **Repetition & hold tracking** — counts reps for dynamic moves and times your longest hold for static ones.
- 💬 **Corrective feedback** — exercise-specific on-screen tips when your form breaks down.
- 🎬 **Offline tutorial library** — short demo videos play locally inside the app (nothing streamed).
- 🏆 **Gamification** — earn badges and build workout streaks to stay motivated.
- 📊 **Session history** — accuracy scores, reps, and streaks saved to your account.
- 🌗 **Dark & light mode** — full theme support.
- 🔒 **Privacy-first** — camera frames are processed on-device; only numerical results (never video) are synced.

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (Dart) |
| Pose detection | Google ML Kit Pose Detection (33 body landmarks) |
| Classification | K-Nearest Neighbors (k = 5, Z-score normalized, Euclidean distance) |
| Backend | Firebase Auth (anonymous) + Cloud Firestore |
| Local storage | SharedPreferences (terms acceptance) |
| Media | camera, video_player |
| ML training pipeline | Python (MediaPipe + scikit-learn), offline |

---

## 📱 How It Works

1. **Pick an exercise** from the Dashboard or a tutorial.
2. **Set up your phone** at the correct camera angle (left-side view for most exercises, back view for Pull-Up).
3. **Move** — the app tracks your skeleton live and flags incorrect form frame by frame.
4. **Finish** — you get a session accuracy score, rep count or longest hold, and any badges you earned.

The KNN model was trained offline on labelled video of correct and incorrect executions, then exported to `assets/knn_training_data.json` for on-device inference.

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart SDK ^3.12.2)
- Android Studio or VS Code with the Flutter extension
- A Firebase project (for auth + session storage)

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/jastinejabonete-eng/flexwell_flutter.git
cd flexwell_flutter

# 2. Install dependencies
flutter pub get

# 3. Add your Firebase config
#    Run `flutterfire configure` to generate lib/firebase_options.dart
#    and place google-services.json in android/app/.
#    (These are git-ignored and must be supplied per environment.)

# 4. Run the app
flutter run
```

> **Note:** `lib/firebase_options.dart` and `android/app/google-services.json` are
> intentionally **not** committed. Generate them with `flutterfire configure`
> for your own Firebase project before building.

---

## 📂 Project Structure

```
lib/
├── main.dart                  # App entry point
├── main_navigation_screen.dart# Bottom navigation shell
├── camera_screen.dart         # Live camera + real-time analysis
├── pose_analyzer.dart         # Feature extraction & per-exercise logic
├── pose_painter.dart          # Skeleton overlay rendering
├── knn_core.dart              # KNN inference (k=5, Z-score)
├── knn_classifier.dart        # Model loading from assets
├── knn_worker.dart            # Background inference isolate
├── form_smoother.dart         # Temporal smoothing of verdicts
├── achievement_service.dart   # Badges & session recording
├── achievements_screen.dart   # Badges display
├── dashboard_screen.dart      # Exercise list & streaks
├── summary_screen.dart        # Post-session results
├── tutorials_screen.dart      # Offline video tutorials
├── user_manual_screen.dart    # In-app user manual
├── terms_screen.dart          # Terms & Conditions gate
├── settings_screen.dart       # App settings
├── app_colors.dart            # Theme palette
└── ...

assets/
├── knn_training_data.json     # Trained KNN model (per-exercise)
├── videos/                    # Offline tutorial videos
└── images/                    # App imagery

DATASET_FLEXWELL/dataset/      # Offline ML training pipeline (Python)
```

---

## 🧪 Model Performance

Evaluated with **video-grouped cross-validation** (no clip leaks between train/test):

| Exercise | Grouped-CV Accuracy | Source Videos | Training Rows |
|----------|--------------------:|--------------:|--------------:|
| Push-Up | 86% | 71 | 78 |
| Squat | 85% | 28 | 28 |
| Plank | 80% | 72 | 2,273 |
| Side Plank | 80% | 115 | 3,570 |
| Lunge | 70% | 80 | 3,097 |
| Pull-Up | 70% | 67 | 97 |

> Squat's small sample size reflects a single-person, one-rep-per-clip recording
> protocol; accuracy should improve with more diverse data.

---

## ⚠️ Disclaimer

FlexWell is a supplementary training tool. It does **not** replace the guidance of
a certified fitness trainer, physical therapist, or medical professional. Exercise
carries inherent risk — use at your own discretion and consult a professional if
you have any medical conditions or prior injuries.

---

## 👤 Author

**Jastine Jabonete** — City College of Calamba
[github.com/jastinejabonete-eng](https://github.com/jastinejabonete-eng)

---

## 📄 License

This project was developed for academic purposes.
