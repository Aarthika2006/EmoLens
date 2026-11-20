# EmoSense ML Pipeline

Machine learning pipeline for training and deploying an emotion recognition model
for individuals with Down syndrome, optimized for real-time inference on Android
via TensorFlow Lite.

## Overview

This pipeline trains a **MobileNetV2 + Squeeze-and-Excitation (SE) attention** model
to classify facial expressions into three emotions: **Happy**, **Neutral**, and **Sad**.
The model processes face crops from an ESP32-CAM and runs on Android via TFLite.

## Dataset

- **Source**: `downSyndrome_sorted.zip` (~30.6 MB)
- **Classes**: Happy (836), Neutral (581), Sad (83) — **heavily imbalanced**
- **Split**: 70% train / 15% val / 15% test (stratified, seed=42)
- **⚠ Note**: No identity info available, so subject-disjoint splits are not guaranteed

## Preprocessing Contract

> **CRITICAL**: The Flutter app MUST replicate this preprocessing exactly.

1. **Face Detection**: MediaPipe FaceDetection (`model_selection=1`, `min_confidence=0.5`)
2. **Crop**: Face bounding box with **20% padding** on each side
3. **Resize**: 224×224 pixels (bilinear interpolation)
4. **Normalize**: `pixel = (pixel / 127.5) - 1.0` → range **[-1.0, 1.0]**
   - This is equivalent to `tf.keras.applications.mobilenet_v2.preprocess_input()`

## Files

| File | Description |
|------|-------------|
| `requirements.txt` | Python dependencies |
| `train.py` | Main training script (GPU auto-detect, Colab-compatible) |
| `evaluate.py` | Evaluation: metrics, confusion matrix, ROC, PR, Grad-CAM |
| `export_tflite.py` | Export to TFLite (float16 + int8 quantization) |
| `collect_from_esp32.py` | Capture frames from ESP32-CAM for dataset expansion |
| `mock_esp32_server.py` | Mock ESP32-CAM server for testing without hardware |
| `adaptive_personalization.py` | Fine-tune on caregiver corrections |
| `README.md` | This file |

## Quick Start

### 1. Install dependencies

```bash
pip install -r requirements.txt
```

### 2. Train the model

```bash
# Train the adaptive model (MobileNetV2 + SE) — recommended
python train.py

# Train baseline CNN for comparison
python train.py --model baseline

# Train both models
python train.py --model both

# Use focal loss for better handling of class imbalance
python train.py --use-focal-loss

# Custom epochs
python train.py --epochs-phase1 20 --epochs-phase2 30
```

The script will:
1. Extract the dataset ZIP (if not already extracted)
2. Detect and crop faces using MediaPipe
3. Split data 70/15/15 (stratified)
4. Train with class balancing and augmentation
5. Save the best model to `saved_models/`

### 3. Evaluate

```bash
python evaluate.py
```

Generates metrics and plots in `docs/results/`:
- Confusion matrix
- ROC curves (one-vs-rest)
- Precision-Recall curves
- Grad-CAM visualizations
- Classification report (macro-F1 is the **primary metric**)

### 4. Export to TFLite

```bash
python export_tflite.py
```

Exports to `app/assets/models/`:
- `emotion_model.tflite` — Float16 quantized (primary, < 10 MB)
- `emotion_model_int8.tflite` — Int8 quantized (smaller, faster)
- `labels.txt` — Class names (Happy, Neutral, Sad)

### 5. Data Collection (optional)

```bash
# Collect from real ESP32-CAM
python collect_from_esp32.py --ip 192.168.1.100 --label Happy

# Or test with mock server
python mock_esp32_server.py --dataset-dir ../dataset/downSyndrome
# Then in another terminal:
python collect_from_esp32.py --ip localhost --label Neutral
```

### 6. Adaptive Personalization (optional)

```bash
python adaptive_personalization.py \
    --corrections-dir path/to/corrections/ \
    --base-model saved_models/adaptive_model/best_model.keras
```

## Model Architecture

### Adaptive Model (Primary)

```
Input (224×224×3, [-1,1])
  │
  ├─ MobileNetV2 (ImageNet weights)
  │   └─ Top 30 layers fine-tuned in Phase 2
  │
  ├─ Squeeze-and-Excitation Block (channel attention)
  │
  ├─ GlobalAveragePooling2D
  ├─ Dropout(0.3)
  ├─ Dense(128, ReLU)
  ├─ Dropout(0.2)
  └─ Dense(3, Softmax) → [Happy, Neutral, Sad]
```

### Training Strategy

| Phase | Layers | Epochs | Learning Rate | Purpose |
|-------|--------|--------|---------------|---------|
| 1 | Head only (backbone frozen) | 20 | 1e-3 | Learn classifier |
| 2 | Top 30 backbone layers + head | 30 | 1e-5 | Fine-tune features |

### Class Imbalance Handling

- **Class weights**: Inversely proportional to frequency
- **Oversampling**: Minority class (Sad) repeated to balance dataset
- **Augmentation**: Heavier for Sad class (flip, rotation, brightness, zoom, blur, JPEG artifacts)
- **ESP32 quality simulation**: Low-res downscale + JPEG compression for Sad class
- **Focal loss**: Optional (`--use-focal-loss`), focuses on hard examples

## Output Structure

```
Capstone/
├── ml/
│   ├── train.py
│   ├── evaluate.py
│   ├── export_tflite.py
│   ├── collect_from_esp32.py
│   ├── mock_esp32_server.py
│   ├── adaptive_personalization.py
│   ├── requirements.txt
│   ├── README.md
│   └── saved_models/
│       ├── adaptive_model/
│       │   ├── best_model.keras
│       │   └── training_log.csv
│       ├── baseline_cnn/
│       │   ├── best_model.keras
│       │   └── training_log.csv
│       └── test_data/
│           ├── X_test.npy
│           └── y_test.npy
├── dataset/
│   ├── downSyndrome/          # Raw images
│   │   ├── Happy/ (836)
│   │   ├── Neutral/ (581)
│   │   └── Sad/ (83)
│   └── processed/             # Face-cropped 224×224
│       ├── Happy/
│       ├── Neutral/
│       └── Sad/
├── app/assets/models/
│   ├── emotion_model.tflite   # Float16 (primary)
│   ├── emotion_model_int8.tflite  # Int8 (alternative)
│   └── labels.txt
└── docs/results/
    ├── confusion_matrix.png
    ├── roc_curves.png
    ├── precision_recall_curves.png
    ├── gradcam_visualizations.png
    └── adaptive_model_training_curves.png
```

## Reproducibility

All random operations are seeded with `SEED=42`:
- Python `random.seed(42)`
- NumPy `np.random.seed(42)`
- TensorFlow `tf.random.set_seed(42)`
- `PYTHONHASHSEED=42`
- `TF_DETERMINISTIC_OPS=1`
- Stratified splits with `random_state=42`

## GPU Support

The training script auto-detects GPU availability:
- **GPU available**: Uses GPU with memory growth enabled
- **No GPU**: Falls back to CPU (slower but functional)
- **Colab**: Works out of the box with Colab GPU runtime
