# Multi-View Fitness Exercise Video Dataset

## Dataset Overview

This repository contains a multi-view fitness exercise video dataset collected for research in exercise recognition, human action analysis, posture assessment, and good/bad exercise form classification.

The dataset includes videos captured from three different camera viewpoints for multiple participants performing seven common fitness exercises with both correct and incorrect execution.

---

## Dataset Statistics

- Number of Subjects: 26
- Number of Exercise Categories: 7
- Exercise Classes:
  - Abs
  - Back
  - Bicep Curl
  - Push-up
  - Shoulder
  - Squat
  - Tricep

- Exercise Form:
  - Good
  - Bad

- Camera Views:
  - Front
  - Side
  - Diagonal

- Video Format: MP4

---

# Dataset Organizations

To support different research workflows, the dataset is provided in three folder organizations.

---

## 1. Dataset Subject-wise

Folder Structure

Dataset Subject-wise/

    subject_001/
        abs/
            good/
                front/
                side/
                diagonal/
            bad/
        back/
        ...
    subject_026/

### Purpose

This organization is useful for:

- Subject-specific analysis
- Cross-subject training and testing
- Person-independent evaluation
- Human action recognition studies

---

## 2. Dataset Exercise-wise

Folder Structure

Dataset Exercise-wise/

    abs/
        good/
            front/
            side/
            diagonal/
        bad/
            front/
            side/
            diagonal/

    back/
    bicep_curl/
    push_up/
    shoulder/
    squat/
    tricep/

### Purpose

This organization is designed for:

- Exercise classification
- Posture estimation
- Exercise recognition
- Multi-view deep learning models

Each camera view is stored separately.

---

## 3. Dataset Exercise Quality

Folder Structure

dataset_exercise_quality/

    abs/
        good/
            subject_001_abs_good_front.mp4
            subject_001_abs_good_side.mp4
            ...
        bad/
            ...

    back/
    bicep_curl/
    push_up/
    shoulder/
    squat/
    tricep/

### Purpose

This organization groups all camera views together inside each quality folder.

It is suitable for:

- Good vs. Bad exercise classification
- Binary posture quality assessment
- Quality prediction models
- Researchers who do not require view-specific folder separation

---

# File Naming Convention

Each video follows the naming format:

subject_<ID>_<exercise>_<quality>_<view>.mp4

Example:

subject_005_push_up_good_front.mp4

where

- subject_005 → Participant ID
- push_up → Exercise category
- good → Exercise quality
- front → Camera viewpoint

---

# Applications

This dataset can be used for:

- Human Activity Recognition
- Exercise Recognition
- Exercise Form Assessment
- Computer Vision
- Deep Learning
- Machine Learning
- Pose Estimation
- Rehabilitation Systems
- Sports Analytics
- AI-based Fitness Coaching

---

