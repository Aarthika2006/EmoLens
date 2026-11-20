# EmoLens — System Architecture

This document describes the architecture of EmoLens at three levels: the overall system, the ML training pipeline, and the Flutter mobile application.

---

## Table of Contents

- [1. System Architecture](#1-system-architecture)
- [2. Data Flow Overview](#2-data-flow-overview)
- [3. ML Pipeline Architecture](#3-ml-pipeline-architecture)
- [4. App Architecture (Clean Architecture)](#4-app-architecture-clean-architecture)
- [5. Adaptive Learning Flow](#5-adaptive-learning-flow)
- [6. Network Communication](#6-network-communication)

---

## 1. System Architecture

The EmoLens system consists of three major subsystems: the **ESP32-CAM** hardware module, the **ML training pipeline** (offline, on a development machine), and the **Flutter mobile app** (on-device inference).

```mermaid
flowchart TB
    subgraph HW ["Hardware Layer"]
        ESP["🎥 ESP32-CAM<br/>OV2640 Sensor<br/>AI-Thinker Board"]
    end

    subgraph NET ["Wi-Fi Network"]
        HTTP["HTTP Endpoints<br/>/capture (JPEG)<br/>:81/stream (MJPEG)"]
    end

    subgraph PHONE ["Mobile Device"]
        subgraph APP ["Flutter App"]
            CS["Camera Service"]
            FD["Face Detection<br/>(Google ML Kit)"]
            EC["Emotion Classifier<br/>(TFLite Runtime)"]
            SM["Smoothing<br/>(EMA Filter)"]
            DB["Local Database<br/>(SQLite)"]
            UI["Dashboard UI<br/>(Charts, History, Stats)"]
        end
        MODEL["emotion_model.tflite<br/>(MobileNetV2 + SE)"]
    end

    subgraph DEV ["Development Machine"]
        subgraph ML ["ML Pipeline"]
            DATA["Dataset<br/>(Down Syndrome Emotions)"]
            TRAIN["train.py<br/>(Transfer Learning)"]
            EVAL["evaluate.py<br/>(Metrics & Plots)"]
            EXPORT["export_tflite.py<br/>(Quantized Export)"]
        end
    end

    ESP -->|"JPEG / MJPEG<br/>over Wi-Fi"| HTTP
    HTTP -->|"HTTP GET"| CS
    CS --> FD
    FD -->|"Cropped Face<br/>224×224"| EC
    EC -->|"Probabilities"| SM
    SM -->|"Smoothed Result"| UI
    SM -->|"Log Entry"| DB
    EC ---|"Loads"| MODEL

    DATA --> TRAIN
    TRAIN --> EVAL
    EVAL --> EXPORT
    EXPORT -->|"Deploy .tflite"| MODEL
```

### Component Summary

| Component | Technology | Responsibility |
|---|---|---|
| ESP32-CAM | Arduino / C++ | Capture and serve JPEG frames over HTTP |
| Camera Service | Dart (http package) | Pull frames via HTTP GET or parse MJPEG stream |
| Face Detection | Google ML Kit | Detect and crop face regions from frames |
| Emotion Classifier | TFLite (MobileNetV2+SE) | Classify cropped face as Happy / Neutral / Sad |
| Smoothing | EMA Filter | Temporal smoothing to reduce prediction jitter |
| Local Database | SQLite (sqflite) | Store session history, emotion logs, corrections |
| Dashboard UI | Flutter (Riverpod, fl_chart) | Real-time display, charts, session management |
| ML Pipeline | Python (TensorFlow, MediaPipe) | Train, evaluate, and export the emotion model |

---

## 2. Data Flow Overview

### Real-Time Inference Flow

```mermaid
sequenceDiagram
    participant ESP as ESP32-CAM
    participant CS as Camera Service
    participant FD as Face Detector
    participant EC as Emotion Classifier
    participant UI as Dashboard UI
    participant DB as SQLite DB

    loop Every Frame
        CS->>ESP: HTTP GET /capture
        ESP-->>CS: JPEG frame (bytes)
        CS->>FD: Raw frame
        FD->>FD: Detect face bounding box
        alt Face detected
            FD->>EC: Cropped face (224×224, normalized [-1,1])
            EC->>EC: TFLite inference
            EC-->>UI: Emotion + confidence
            UI->>UI: Update chart & label
            UI->>DB: Log emotion entry
        else No face
            FD-->>UI: "No face detected"
        end
    end
```

### Data Processing Modes

The app supports two frame acquisition modes:

| Mode | Endpoint | Description |
|---|---|---|
| **Capture Polling** | `GET http://<IP>/capture` | Requests individual JPEG frames at a configurable interval. More reliable on constrained networks. |
| **MJPEG Streaming** | `GET http://<IP>:81/stream` | Continuous MJPEG stream. Lower latency but higher bandwidth usage. Uses boundary-based frame parsing. |

---

## 3. ML Pipeline Architecture

The ML pipeline transforms raw images into a deployable TFLite model through five stages.

```mermaid
flowchart LR
    subgraph STAGE1 ["Stage 1: Data Preparation"]
        RAW["Raw Dataset<br/>836 Happy<br/>581 Neutral<br/>83 Sad"]
        VERIFY["Image Verification<br/>(Remove Corrupt)"]
        FACE["Face Detection<br/>(MediaPipe)"]
        CROP["Face Crop & Resize<br/>(224×224)"]
        RAW --> VERIFY --> FACE --> CROP
    end

    subgraph STAGE2 ["Stage 2: Data Splitting & Augmentation"]
        SPLIT["Stratified Split<br/>70/15/15<br/>(seed=42)"]
        AUG["Augmentation<br/>(Heavy on Sad class)"]
        WEIGHTS["Class Weight<br/>Computation"]
        CROP --> SPLIT
        SPLIT --> AUG
        SPLIT --> WEIGHTS
    end

    subgraph STAGE3 ["Stage 3: Model Training"]
        BASE["Baseline CNN<br/>(3-4 Conv Blocks)"]
        MBNET["MobileNetV2 + SE<br/>(Transfer Learning)"]
        P1["Phase 1: Freeze Backbone<br/>Train Head (20 epochs)"]
        P2["Phase 2: Unfreeze Top 30<br/>Fine-tune (30 epochs, lr=1e-5)"]
        AUG --> BASE
        AUG --> MBNET
        WEIGHTS --> MBNET
        MBNET --> P1 --> P2
    end

    subgraph STAGE4 ["Stage 4: Evaluation"]
        METRICS["Accuracy, F1, P/R"]
        CM["Confusion Matrix"]
        ROC["ROC & PR Curves"]
        GCAM["Grad-CAM"]
        P2 --> METRICS
        P2 --> CM
        P2 --> ROC
        P2 --> GCAM
    end

    subgraph STAGE5 ["Stage 5: Export"]
        FP16["Float16 TFLite"]
        INT8["Int8 TFLite"]
        VERIFY2["Output Verification"]
        P2 --> FP16
        P2 --> INT8
        FP16 --> VERIFY2
    end
```

### Augmentation Strategy

Due to severe class imbalance (Happy 836 : Neutral 581 : **Sad 83**), heavy augmentation is applied, particularly to the minority class:

| Augmentation | Purpose |
|---|---|
| Horizontal flip | Mirror invariance |
| Rotation (±15°) | Pose variation |
| Brightness / contrast jitter | Lighting robustness |
| Random zoom | Scale invariance |
| Gaussian blur / noise | Sensor noise simulation |
| JPEG compression artifacts | Simulate ESP32-CAM OV2640 image quality |
| Low-resolution downscale | Simulate real-world camera resolution |

### Preprocessing

> **Critical:** The Flutter app must replicate this preprocessing exactly.

```
Input image → Resize to 224×224 → Convert to float32 → Normalize to [-1, 1]
```

Normalization uses `tf.keras.applications.mobilenet_v2.preprocess_input`, which maps pixel values from `[0, 255]` to `[-1, 1]` using the formula: `pixel / 127.5 - 1.0`.

---

## 4. App Architecture (Clean Architecture)

The Flutter app follows **Clean Architecture** principles with clear separation of concerns.

```mermaid
flowchart TB
    subgraph PRESENTATION ["Presentation Layer"]
        SCREENS["Screens<br/>Live Feed / Dashboard /<br/>Settings / History / Onboarding"]
        WIDGETS["Widgets<br/>Emotion Card / Chart /<br/>Camera Preview"]
        PROVIDERS["Providers<br/>(Riverpod StateNotifiers)"]
    end

    subgraph DOMAIN ["Domain Layer"]
        ENTITIES["Entities<br/>EmotionResult / Session /<br/>CameraConfig"]
        USECASES["Use Cases<br/>ClassifyEmotion / StartSession /<br/>ExportData / SaveCorrection"]
        REPO_IF["Repository Interfaces"]
    end

    subgraph DATA ["Data Layer"]
        REPO_IMPL["Repository Implementations"]
        DS_LOCAL["Local Data Sources<br/>(SQLite, SharedPreferences)"]
        DS_REMOTE["Remote Data Sources<br/>(ESP32-CAM HTTP Client)"]
    end

    subgraph SERVICES ["Services Layer"]
        CAMERA_SVC["CameraService<br/>(HTTP / MJPEG)"]
        FACE_SVC["FaceDetectionService<br/>(Google ML Kit)"]
        TFLITE_SVC["TFLiteService<br/>(Emotion Model)"]
    end

    SCREENS --> PROVIDERS
    PROVIDERS --> USECASES
    USECASES --> REPO_IF
    REPO_IF --> REPO_IMPL
    REPO_IMPL --> DS_LOCAL
    REPO_IMPL --> DS_REMOTE
    PROVIDERS --> SERVICES
    SERVICES --> DS_REMOTE

    style DOMAIN fill:#e8f5e9
    style PRESENTATION fill:#e3f2fd
    style DATA fill:#fff3e0
    style SERVICES fill:#fce4ec
```

### Layer Responsibilities

| Layer | Responsibility | Key Classes |
|---|---|---|
| **Presentation** | UI rendering, user interaction, state management | Screens, Widgets, Riverpod Providers |
| **Domain** | Business logic, entities, use case orchestration | EmotionResult, ClassifyEmotionUseCase |
| **Data** | Data persistence, network communication | SQLite repositories, HTTP clients |
| **Services** | Hardware abstraction, ML inference | CameraService, TFLiteService, FaceDetectionService |

### Navigation

The app uses **GoRouter** for declarative routing:

```
/onboarding → /settings → /live-feed → /dashboard → /history
                              ↕
                          /session/:id
```

---

## 5. Adaptive Learning Flow

EmoLens supports caregiver-driven adaptive personalization to improve accuracy for a specific individual.

```mermaid
flowchart TB
    LIVE["Live Classification<br/>Predicted: Happy (0.72)"]
    CORRECT["Caregiver Correction<br/>Actual: Neutral"]
    STORE["Store Correction<br/>(Face Crop + Label)<br/>On-Device SQLite"]
    EXPORT["Export Corrections<br/>(ZIP: images + labels.csv)"]
    FINETUNE["Fine-Tune Model<br/>(Last Dense Layers Only)"]
    NEWMODEL["Updated .tflite"]
    DEPLOY["Deploy to Device"]

    LIVE --> CORRECT
    CORRECT --> STORE
    STORE --> EXPORT
    EXPORT --> FINETUNE
    FINETUNE --> NEWMODEL
    NEWMODEL --> DEPLOY
    DEPLOY --> LIVE

    style CORRECT fill:#fff9c4
    style FINETUNE fill:#e8f5e9
```

### Adaptive Learning Details

| Aspect | Detail |
|---|---|
| **What is stored** | Cropped face image (224×224) + correct label |
| **Where** | On-device in app-private storage |
| **Fine-tuning scope** | Only the final Dense layers (to prevent catastrophic forgetting) |
| **Tool** | `ml/adaptive_personalization.py` |
| **Limitations** | Small correction set may yield modest gains; no identity-aware training |

---

## 6. Network Communication

### ESP32-CAM HTTP Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `http://<IP>/capture` | GET | Returns a single JPEG frame |
| `http://<IP>:81/stream` | GET | Returns a continuous MJPEG stream |
| `http://<IP>/status` | GET | Returns camera status JSON |
| `http://<IP>/control?var=<name>&val=<value>` | GET | Set camera parameter (resolution, quality, etc.) |

### MJPEG Stream Format

The MJPEG stream uses the boundary string `123456789000000000000987654321`:

```
--123456789000000000000987654321\r\n
Content-Type: image/jpeg\r\n
Content-Length: <size>\r\n
\r\n
<JPEG bytes>
```

The app's stream parser reads frames by scanning for boundary markers and extracting JPEG payloads between them.

---

> **See also:**
> - [Model Report](model_report.md) — Training methodology and evaluation results
> - [Privacy Policy](privacy_policy.md) — Data handling and ethical considerations
> - [Root README](../README.md) — Setup and usage instructions
