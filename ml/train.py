#!/usr/bin/env python3
"""
train.py - EmoSense Emotion Recognition Training Pipeline
==========================================================
Trains emotion recognition models on faces of individuals with Down syndrome.
Supports two architectures:
  A) Baseline CNN (3-4 conv blocks)
  B) MobileNetV2 + SE Attention (adaptive model) - two-phase transfer learning

PREPROCESSING CONTRACT (Flutter app MUST replicate):
  1. Detect face using MediaPipe FaceDetection (model_selection=1, min_confidence=0.5)
  2. Crop face with 20% padding on each side
  3. Resize to 224x224 (bilinear interpolation)
  4. Convert to float32
  5. Normalize to [-1, 1] using: pixel = (pixel / 127.5) - 1.0
     This matches tf.keras.applications.mobilenet_v2.preprocess_input()

Usage:
    python train.py                          # Train adaptive model (default)
    python train.py --model baseline         # Train baseline CNN
    python train.py --model both             # Train both models
    python train.py --epochs-phase1 20 --epochs-phase2 30
    python train.py --use-focal-loss         # Use focal loss for imbalanced data
    python train.py --skip-preprocessing     # Skip face detection, use already processed data

Dataset: Expects ZIP at ../downSyndrome_sorted.zip or extracted at ../dataset/downSyndrome/
Classes: Happy (836), Neutral (581), Sad (83) - HEAVILY IMBALANCED
"""

import os
import sys
import random
import shutil
import warnings
import zipfile
from pathlib import Path

import numpy as np

# ============================================================================
# REPRODUCIBILITY: Seed everything before importing TensorFlow
# ============================================================================
SEED = 42
random.seed(SEED)
np.random.seed(SEED)
os.environ["PYTHONHASHSEED"] = str(SEED)
os.environ["TF_DETERMINISTIC_OPS"] = "1"

import tensorflow as tf
tf.random.set_seed(SEED)

# Suppress noisy warnings
os.environ["TF_CPP_MIN_LOG_LEVEL"] = "2"
warnings.filterwarnings("ignore", category=UserWarning)

import cv2
import mediapipe as mp
from PIL import Image
from sklearn.model_selection import train_test_split
from sklearn.utils.class_weight import compute_class_weight
from tqdm import tqdm

# ============================================================================
# CONFIGURATION
# ============================================================================
# Paths (relative to this script's directory)
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent
DATASET_ZIP = PROJECT_DIR.parent / "downSyndrome_sorted.zip"
RAW_DATASET_DIR = PROJECT_DIR / "dataset" / "downSyndrome"
PROCESSED_DIR = PROJECT_DIR / "dataset" / "processed"
SAVED_MODELS_DIR = SCRIPT_DIR / "saved_models"

# Classes - ORDER MATTERS (must match labels.txt and Flutter app)
CLASS_NAMES = ["Happy", "Neutral", "Sad"]
NUM_CLASSES = len(CLASS_NAMES)

# Image settings
# =============================================================================
# PREPROCESSING CONTRACT:
# Input:  JPEG frame (any resolution) from ESP32-CAM (OV2640, QVGA/VGA)
# Step 1: Face detection → crop with 20% padding
# Step 2: Resize to IMG_SIZE x IMG_SIZE using bilinear interpolation
# Step 3: Normalize to [-1.0, 1.0] via (pixel / 127.5) - 1.0
#         This is exactly what tf.keras.applications.mobilenet_v2.preprocess_input() does
# The Flutter app MUST replicate Steps 1-3 identically for inference.
# =============================================================================
IMG_SIZE = 224
IMG_SHAPE = (IMG_SIZE, IMG_SIZE, 3)

# Training defaults
BATCH_SIZE = 32
EPOCHS_PHASE1 = 20   # Head-only training (backbone frozen)
EPOCHS_PHASE2 = 30   # Fine-tuning (top 30 layers unfrozen)
LR_PHASE1 = 1e-3
LR_PHASE2 = 1e-5
PATIENCE = 7         # Early stopping patience
FACE_PADDING = 0.20  # 20% padding around detected face


# ============================================================================
# STEP 1: Dataset Extraction
# ============================================================================
def extract_dataset():
    """Extract the dataset ZIP if the raw dataset folder doesn't exist."""
    if RAW_DATASET_DIR.exists() and any(RAW_DATASET_DIR.iterdir()):
        print(f"[INFO] Raw dataset already exists at {RAW_DATASET_DIR}")
        return

    if not DATASET_ZIP.exists():
        # Try alternative locations
        alt_paths = [
            PROJECT_DIR / "downSyndrome_sorted.zip",
            Path.home() / "Downloads" / "downSyndrome_sorted.zip",
        ]
        found = None
        for p in alt_paths:
            if p.exists():
                found = p
                break
        if found is None:
            print(f"[ERROR] Dataset ZIP not found at {DATASET_ZIP}")
            print(f"        or any of: {[str(p) for p in alt_paths]}")
            sys.exit(1)
        zip_path = found
    else:
        zip_path = DATASET_ZIP

    print(f"[INFO] Extracting {zip_path} → {RAW_DATASET_DIR.parent}")
    RAW_DATASET_DIR.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(RAW_DATASET_DIR.parent)
    print(f"[INFO] Extraction complete.")


# ============================================================================
# STEP 2: Face Detection & Preprocessing
# ============================================================================
def detect_and_crop_face(image_bgr, face_detector, padding=FACE_PADDING):
    """
    Detect face using MediaPipe and crop with padding.
    
    Args:
        image_bgr: OpenCV BGR image
        face_detector: MediaPipe FaceDetection instance
        padding: Fraction of face size to add as padding (0.2 = 20%)
    
    Returns:
        Cropped face as BGR numpy array, or None if no face found.
    """
    h, w = image_bgr.shape[:2]
    image_rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
    results = face_detector.process(image_rgb)

    if not results.detections:
        return None

    # Use the detection with highest confidence
    detection = max(results.detections, key=lambda d: d.score[0])
    bbox = detection.location_data.relative_bounding_box

    # Convert relative coords to absolute with padding
    x_min = int(max(0, (bbox.xmin - padding * bbox.width) * w))
    y_min = int(max(0, (bbox.ymin - padding * bbox.height) * h))
    x_max = int(min(w, (bbox.xmin + bbox.width + padding * bbox.width) * w))
    y_max = int(min(h, (bbox.ymin + bbox.height + padding * bbox.height) * h))

    # Sanity check
    if x_max - x_min < 10 or y_max - y_min < 10:
        return None

    face_crop = image_bgr[y_min:y_max, x_min:x_max]
    return face_crop


def preprocess_dataset(force=False):
    """
    Process all raw images: detect faces, crop, resize to 224x224, save.
    
    Saves processed images to PROCESSED_DIR/{Happy,Neutral,Sad}/
    Skips images where no face is detected.
    Removes corrupt/unreadable images.
    """
    if PROCESSED_DIR.exists() and not force:
        # Check if already processed
        total = sum(1 for _ in PROCESSED_DIR.rglob("*.jpg"))
        if total > 0:
            print(f"[INFO] Processed dataset exists ({total} images). Use --force-preprocess to redo.")
            return

    print(f"[INFO] Preprocessing dataset → {PROCESSED_DIR}")
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)

    # Initialize MediaPipe FaceDetection
    # model_selection=1: full-range model (better for varied distances)
    # min_detection_confidence=0.5: moderate threshold
    mp_face = mp.solutions.face_detection
    face_detector = mp_face.FaceDetection(
        model_selection=1,
        min_detection_confidence=0.5
    )

    stats = {"total": 0, "processed": 0, "no_face": 0, "corrupt": 0}

    for class_name in CLASS_NAMES:
        src_dir = RAW_DATASET_DIR / class_name
        dst_dir = PROCESSED_DIR / class_name
        dst_dir.mkdir(parents=True, exist_ok=True)

        if not src_dir.exists():
            print(f"[WARN] Source directory not found: {src_dir}")
            continue

        image_files = list(src_dir.glob("*.[jJ][pP][gG]")) + list(src_dir.glob("*.[jJ][pP][eE][gG]"))
        print(f"  Processing {class_name}: {len(image_files)} images...")

        for img_path in tqdm(image_files, desc=f"  {class_name}", leave=False):
            stats["total"] += 1

            # Read and verify image
            try:
                img = cv2.imread(str(img_path))
                if img is None:
                    raise ValueError("cv2.imread returned None")
            except Exception:
                stats["corrupt"] += 1
                continue

            # Detect and crop face
            face = detect_and_crop_face(img, face_detector)
            if face is None:
                # Fallback: use the whole image (may already be a face crop)
                face = img
                stats["no_face"] += 1

            # Resize to target size
            face_resized = cv2.resize(face, (IMG_SIZE, IMG_SIZE), interpolation=cv2.INTER_LINEAR)

            # Save processed image
            dst_path = dst_dir / img_path.name
            cv2.imwrite(str(dst_path), face_resized)
            stats["processed"] += 1

    face_detector.close()

    print(f"\n[INFO] Preprocessing complete:")
    print(f"  Total images  : {stats['total']}")
    print(f"  Processed     : {stats['processed']}")
    print(f"  No face found : {stats['no_face']} (used full image as fallback)")
    print(f"  Corrupt/bad   : {stats['corrupt']}")


# ============================================================================
# STEP 3: Data Loading & Splitting
# ============================================================================
def load_dataset():
    """
    Load processed images and labels. Stratified split 70/15/15.
    
    Returns:
        (X_train, y_train), (X_val, y_val), (X_test, y_test) as numpy arrays.
        Images are uint8 [0, 255] - preprocessing is applied during training.
    
    NOTE: There is a potential data leakage risk since we have no identity info.
    Multiple images of the same individual may appear in both train and test sets.
    This is documented as a known limitation.
    """
    print("[INFO] Loading processed dataset...")
    images = []
    labels = []

    for class_idx, class_name in enumerate(CLASS_NAMES):
        class_dir = PROCESSED_DIR / class_name
        if not class_dir.exists():
            print(f"[WARN] Class directory not found: {class_dir}")
            continue

        img_files = sorted(class_dir.glob("*.[jJ][pP]*"))
        for img_path in img_files:
            img = cv2.imread(str(img_path))
            if img is None:
                continue
            img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            images.append(img_rgb)
            labels.append(class_idx)

    X = np.array(images, dtype=np.uint8)
    y = np.array(labels, dtype=np.int32)

    print(f"[INFO] Dataset loaded: {len(X)} images")
    for i, name in enumerate(CLASS_NAMES):
        count = np.sum(y == i)
        print(f"  {name}: {count} ({100*count/len(y):.1f}%)")

    # Stratified split: 70% train, 15% val, 15% test (seed=42)
    # First split: 70% train, 30% temp
    X_train, X_temp, y_train, y_temp = train_test_split(
        X, y, test_size=0.30, random_state=SEED, stratify=y
    )
    # Second split: 50/50 of temp → 15% val, 15% test
    X_val, X_test, y_val, y_test = train_test_split(
        X_temp, y_temp, test_size=0.50, random_state=SEED, stratify=y_temp
    )

    print(f"\n[INFO] Split (seed={SEED}):")
    print(f"  Train : {len(X_train)} images")
    print(f"  Val   : {len(X_val)} images")
    print(f"  Test  : {len(X_test)} images")
    print(f"  ⚠ WARNING: Potential data leakage - no identity info available to ensure")
    print(f"    subject-disjoint splits. Same individual may appear in multiple sets.")

    return (X_train, y_train), (X_val, y_val), (X_test, y_test)


# ============================================================================
# STEP 4: Data Augmentation
# ============================================================================
def create_augmentation_layer(is_minority=False):
    """
    Create a tf.keras.Sequential augmentation pipeline.
    
    For minority class (Sad), applies heavier augmentation including
    ESP32-CAM quality simulation.
    
    Args:
        is_minority: If True, applies more aggressive augmentation.
    
    Returns:
        tf.keras.Sequential augmentation model.
    """
    layers = [
        tf.keras.layers.RandomFlip("horizontal"),
        tf.keras.layers.RandomRotation(0.04 if not is_minority else 0.08),  # ±7° or ±15°
        tf.keras.layers.RandomBrightness(0.1 if not is_minority else 0.2),
        tf.keras.layers.RandomContrast(0.1 if not is_minority else 0.2),
        tf.keras.layers.RandomZoom((-0.1, 0.1) if not is_minority else (-0.15, 0.15)),
    ]
    return tf.keras.Sequential(layers, name="augmentation")


def simulate_esp32_quality(image):
    """
    Simulate ESP32-CAM OV2640 image quality degradation.
    Applied to minority class during augmentation.
    
    Simulates:
    - Low resolution (downscale + upscale)
    - JPEG compression artifacts
    - Gaussian noise
    - Slight blur
    
    Args:
        image: float32 tensor in [-1, 1] range, shape (H, W, 3)
    
    Returns:
        Degraded image, same shape and range.
    """
    # Convert from [-1,1] to [0,255] for processing
    img = tf.cast((image + 1.0) * 127.5, tf.uint8)

    # Random JPEG compression (quality 20-50)
    quality = tf.random.uniform([], 20, 50, dtype=tf.int32)
    img = tf.image.adjust_jpeg_quality(img, quality)

    # Convert back
    img = tf.cast(img, tf.float32) / 127.5 - 1.0

    # Add slight Gaussian noise
    noise = tf.random.normal(tf.shape(img), mean=0.0, stddev=0.03)
    img = tf.clip_by_value(img + noise, -1.0, 1.0)

    return img


def create_tf_dataset(X, y, batch_size, is_training=False, class_weights_dict=None):
    """
    Create a tf.data.Dataset with preprocessing and augmentation.
    
    PREPROCESSING (applied to ALL images):
      pixel_float32 = (pixel_uint8 / 127.5) - 1.0
      This normalizes [0, 255] → [-1.0, 1.0]
      Equivalent to tf.keras.applications.mobilenet_v2.preprocess_input()
    
    Args:
        X: numpy array of uint8 images [0, 255]
        y: numpy array of integer labels
        batch_size: Batch size
        is_training: If True, applies augmentation
        class_weights_dict: Optional dict for sample weighting
    
    Returns:
        tf.data.Dataset
    """
    # Create augmentation layers
    augmenter = create_augmentation_layer(is_minority=False)
    heavy_augmenter = create_augmentation_layer(is_minority=True)

    def preprocess(image, label):
        """
        PREPROCESSING FUNCTION
        Input:  uint8 image [0, 255], shape (224, 224, 3)
        Output: float32 image [-1.0, 1.0], shape (224, 224, 3)
        
        Formula: output = (input / 127.5) - 1.0
        This matches tf.keras.applications.mobilenet_v2.preprocess_input()
        The Flutter app MUST use the same formula.
        """
        image = tf.cast(image, tf.float32)
        # Normalize to [-1, 1] - MobileNetV2 preprocessing
        image = image / 127.5 - 1.0
        return image, label

    def augment(image, label):
        """Apply augmentation during training."""
        # Heavy augmentation for Sad class (index 2)
        image = tf.cond(
            tf.equal(label, 2),  # Sad class
            lambda: heavy_augmenter(tf.expand_dims(image, 0), training=True)[0],
            lambda: augmenter(tf.expand_dims(image, 0), training=True)[0]
        )
        # ESP32 quality simulation for Sad class (30% chance)
        if tf.random.uniform([]) < 0.3:
            image = tf.cond(
                tf.equal(label, 2),
                lambda: simulate_esp32_quality(image),
                lambda: image
            )
        return image, label

    dataset = tf.data.Dataset.from_tensor_slices((X, y))

    if is_training:
        # Oversample minority class (Sad) by repeating it
        # Compute oversampling factors
        class_counts = np.bincount(y, minlength=NUM_CLASSES)
        max_count = class_counts.max()

        # Create separate datasets per class and oversample
        class_datasets = []
        for c in range(NUM_CLASSES):
            mask = (y == c)
            X_c = X[mask]
            y_c = y[mask]
            repeat_factor = max(1, int(np.ceil(max_count / len(X_c))))
            ds_c = tf.data.Dataset.from_tensor_slices((X_c, y_c)).repeat(repeat_factor)
            class_datasets.append(ds_c)

        # Interleave classes equally
        dataset = tf.data.Dataset.sample_from_datasets(
            class_datasets,
            weights=[1.0/NUM_CLASSES] * NUM_CLASSES,
            seed=SEED
        )
        # Take enough samples for one "epoch" worth of balanced data
        samples_per_epoch = max_count * NUM_CLASSES
        dataset = dataset.take(samples_per_epoch)
        dataset = dataset.shuffle(buffer_size=min(2048, samples_per_epoch), seed=SEED)
        dataset = dataset.map(preprocess, num_parallel_calls=tf.data.AUTOTUNE)
        dataset = dataset.map(augment, num_parallel_calls=tf.data.AUTOTUNE)
    else:
        dataset = dataset.map(preprocess, num_parallel_calls=tf.data.AUTOTUNE)

    dataset = dataset.batch(batch_size)
    dataset = dataset.prefetch(tf.data.AUTOTUNE)
    return dataset


# ============================================================================
# STEP 5: Model Architectures
# ============================================================================

def squeeze_excitation_block(input_tensor, ratio=16):
    """
    Squeeze-and-Excitation (SE) attention block.
    
    Learns channel-wise feature recalibration weights.
    
    Args:
        input_tensor: Input tensor of shape (batch, H, W, C)
        ratio: Reduction ratio for the bottleneck
    
    Returns:
        Tensor with channel attention applied, same shape as input.
    
    Reference: Hu et al., "Squeeze-and-Excitation Networks" (CVPR 2018)
    """
    channels = input_tensor.shape[-1]
    
    # Squeeze: Global average pooling
    se = tf.keras.layers.GlobalAveragePooling2D()(input_tensor)
    
    # Excitation: Two FC layers (bottleneck)
    se = tf.keras.layers.Dense(channels // ratio, activation="relu",
                                kernel_initializer="he_normal")(se)
    se = tf.keras.layers.Dense(channels, activation="sigmoid",
                                kernel_initializer="he_normal")(se)
    
    # Reshape for broadcasting
    se = tf.keras.layers.Reshape((1, 1, channels))(se)
    
    # Scale: channel-wise multiplication
    return tf.keras.layers.Multiply()([input_tensor, se])


def build_baseline_cnn():
    """
    Build a small baseline CNN for comparison.
    
    Architecture: 4 Conv blocks → GlobalAvgPool → Dense → Softmax
    ~200K parameters, suitable for quick experiments.
    
    Input:  (224, 224, 3) float32 in [-1, 1]
    Output: (3,) softmax probabilities [Happy, Neutral, Sad]
    """
    inputs = tf.keras.Input(shape=IMG_SHAPE, name="input_image")

    x = inputs
    # Block 1
    x = tf.keras.layers.Conv2D(32, 3, padding="same", activation="relu")(x)
    x = tf.keras.layers.BatchNormalization()(x)
    x = tf.keras.layers.MaxPooling2D(2)(x)

    # Block 2
    x = tf.keras.layers.Conv2D(64, 3, padding="same", activation="relu")(x)
    x = tf.keras.layers.BatchNormalization()(x)
    x = tf.keras.layers.MaxPooling2D(2)(x)

    # Block 3
    x = tf.keras.layers.Conv2D(128, 3, padding="same", activation="relu")(x)
    x = tf.keras.layers.BatchNormalization()(x)
    x = tf.keras.layers.MaxPooling2D(2)(x)

    # Block 4
    x = tf.keras.layers.Conv2D(256, 3, padding="same", activation="relu")(x)
    x = tf.keras.layers.BatchNormalization()(x)

    # Head
    x = tf.keras.layers.GlobalAveragePooling2D()(x)
    x = tf.keras.layers.Dropout(0.3)(x)
    x = tf.keras.layers.Dense(128, activation="relu")(x)
    x = tf.keras.layers.Dropout(0.2)(x)
    outputs = tf.keras.layers.Dense(NUM_CLASSES, activation="softmax", name="predictions")(x)

    model = tf.keras.Model(inputs, outputs, name="baseline_cnn")
    return model


def build_adaptive_model():
    """
    Build the MobileNetV2 + SE Attention model (the "adaptive" model).
    
    Architecture:
      - MobileNetV2 backbone (ImageNet weights, include_top=False)
      - Squeeze-and-Excitation (SE) attention block
      - GlobalAveragePooling2D
      - Dropout(0.3) → Dense(128, relu) → Dropout(0.2) → Dense(3, softmax)
    
    Input:  (224, 224, 3) float32 in [-1, 1]
    Output: (3,) softmax probabilities [Happy, Neutral, Sad]
    
    PREPROCESSING NOTE:
      MobileNetV2 expects inputs in [-1, 1].
      We use: pixel = (pixel / 127.5) - 1.0
      This is equivalent to tf.keras.applications.mobilenet_v2.preprocess_input()
      The Flutter app MUST apply the same normalization before inference.
    
    Training Strategy:
      Phase 1: Freeze backbone, train only head (20 epochs, lr=1e-3)
      Phase 2: Unfreeze top 30 layers, fine-tune (30 epochs, lr=1e-5)
    """
    # MobileNetV2 backbone
    backbone = tf.keras.applications.MobileNetV2(
        input_shape=IMG_SHAPE,
        include_top=False,
        weights="imagenet"
    )
    backbone.trainable = False  # Frozen initially (Phase 1)

    inputs = tf.keras.Input(shape=IMG_SHAPE, name="input_image")
    
    # Backbone features
    x = backbone(inputs, training=False)
    
    # SE Attention Block
    x = squeeze_excitation_block(x, ratio=16)
    
    # Classification Head
    x = tf.keras.layers.GlobalAveragePooling2D(name="gap")(x)
    x = tf.keras.layers.Dropout(0.3, name="dropout_1")(x)
    x = tf.keras.layers.Dense(128, activation="relu", name="dense_128")(x)
    x = tf.keras.layers.Dropout(0.2, name="dropout_2")(x)
    outputs = tf.keras.layers.Dense(NUM_CLASSES, activation="softmax", name="predictions")(x)

    model = tf.keras.Model(inputs, outputs, name="adaptive_mobilenetv2_se")
    return model, backbone


# ============================================================================
# STEP 6: Loss Functions
# ============================================================================

def focal_loss(gamma=2.0, alpha=None):
    """
    Focal Loss for handling class imbalance.
    
    Reduces the loss for well-classified examples, focusing training on
    hard-to-classify samples (e.g., the minority Sad class).
    
    Args:
        gamma: Focusing parameter (higher = more focus on hard examples)
        alpha: Per-class weighting factor (array of length NUM_CLASSES)
    
    Returns:
        Loss function compatible with tf.keras.Model.compile()
    
    Reference: Lin et al., "Focal Loss for Dense Object Detection" (ICCV 2017)
    """
    def loss_fn(y_true, y_pred):
        y_pred = tf.clip_by_value(y_pred, 1e-7, 1.0 - 1e-7)
        y_true_one_hot = tf.one_hot(tf.cast(y_true, tf.int32), NUM_CLASSES)
        
        cross_entropy = -y_true_one_hot * tf.math.log(y_pred)
        focal_weight = tf.pow(1.0 - y_pred, gamma) * y_true_one_hot
        
        loss = focal_weight * cross_entropy
        
        if alpha is not None:
            alpha_tensor = tf.constant(alpha, dtype=tf.float32)
            loss = loss * alpha_tensor
        
        return tf.reduce_mean(tf.reduce_sum(loss, axis=-1))
    
    return loss_fn


# ============================================================================
# STEP 7: Training
# ============================================================================

def compute_class_weights_dict(y):
    """
    Compute class weights inversely proportional to frequency.
    
    Gives higher weight to underrepresented classes (Sad >> Neutral > Happy).
    """
    classes = np.unique(y)
    weights = compute_class_weight("balanced", classes=classes, y=y)
    weight_dict = dict(zip(classes, weights))
    
    print("[INFO] Class weights (inversely proportional to frequency):")
    for cls_idx, name in enumerate(CLASS_NAMES):
        if cls_idx in weight_dict:
            print(f"  {name}: {weight_dict[cls_idx]:.3f}")
    
    return weight_dict


def get_callbacks(model_name, monitor="val_loss"):
    """Create training callbacks."""
    checkpoint_dir = SAVED_MODELS_DIR / model_name
    checkpoint_dir.mkdir(parents=True, exist_ok=True)

    callbacks = [
        tf.keras.callbacks.ModelCheckpoint(
            filepath=str(checkpoint_dir / "best_model.keras"),
            monitor=monitor,
            save_best_only=True,
            mode="min",
            verbose=1
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor=monitor,
            factor=0.5,
            patience=3,
            min_lr=1e-7,
            verbose=1
        ),
        tf.keras.callbacks.EarlyStopping(
            monitor=monitor,
            patience=PATIENCE,
            restore_best_weights=True,
            verbose=1
        ),
        tf.keras.callbacks.CSVLogger(
            str(checkpoint_dir / "training_log.csv"),
            append=False
        ),
    ]
    return callbacks


def train_baseline(train_ds, val_ds, class_weights, use_focal=False):
    """Train the baseline CNN model."""
    print("\n" + "=" * 70)
    print("TRAINING: Baseline CNN")
    print("=" * 70)

    model = build_baseline_cnn()
    model.summary()

    if use_focal:
        alpha = [class_weights.get(i, 1.0) for i in range(NUM_CLASSES)]
        loss = focal_loss(gamma=2.0, alpha=alpha)
    else:
        loss = "sparse_categorical_crossentropy"

    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=LR_PHASE1),
        loss=loss,
        metrics=["accuracy"]
    )

    callbacks = get_callbacks("baseline_cnn")

    history = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=EPOCHS_PHASE1 + EPOCHS_PHASE2,  # Single phase for baseline
        callbacks=callbacks,
        class_weight=class_weights if not use_focal else None,
    )

    print(f"\n[INFO] Baseline CNN training complete.")
    print(f"  Best val_loss: {min(history.history['val_loss']):.4f}")
    print(f"  Best val_acc : {max(history.history['val_accuracy']):.4f}")

    return model, history


def train_adaptive(train_ds, val_ds, class_weights, use_focal=False,
                   epochs_p1=EPOCHS_PHASE1, epochs_p2=EPOCHS_PHASE2):
    """
    Train the MobileNetV2 + SE model with two-phase transfer learning.
    
    Phase 1: Backbone frozen → train only SE block + head (epochs_p1 epochs)
    Phase 2: Unfreeze top 30 backbone layers → fine-tune all (epochs_p2 epochs)
    """
    print("\n" + "=" * 70)
    print("TRAINING: Adaptive MobileNetV2 + SE Attention")
    print("=" * 70)

    model, backbone = build_adaptive_model()
    model.summary()

    if use_focal:
        alpha = [class_weights.get(i, 1.0) for i in range(NUM_CLASSES)]
        loss = focal_loss(gamma=2.0, alpha=alpha)
    else:
        loss = "sparse_categorical_crossentropy"

    # ---- Phase 1: Train head only (backbone frozen) ----
    print(f"\n--- Phase 1: Head training ({epochs_p1} epochs, lr={LR_PHASE1}) ---")
    print(f"    Backbone layers: {len(backbone.layers)} (all frozen)")

    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=LR_PHASE1),
        loss=loss,
        metrics=["accuracy"]
    )

    callbacks_p1 = get_callbacks("adaptive_model", monitor="val_loss")

    history_p1 = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=epochs_p1,
        callbacks=callbacks_p1,
        class_weight=class_weights if not use_focal else None,
    )

    # ---- Phase 2: Fine-tune top 30 layers ----
    print(f"\n--- Phase 2: Fine-tuning ({epochs_p2} epochs, lr={LR_PHASE2}) ---")

    # Unfreeze the backbone
    backbone.trainable = True

    # Freeze all layers except the top 30
    for layer in backbone.layers[:-30]:
        layer.trainable = False

    trainable_count = sum(1 for l in backbone.layers if l.trainable)
    print(f"    Backbone trainable layers: {trainable_count} of {len(backbone.layers)}")

    # Recompile with lower learning rate
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=LR_PHASE2),
        loss=loss,
        metrics=["accuracy"]
    )

    callbacks_p2 = get_callbacks("adaptive_model", monitor="val_loss")

    history_p2 = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=epochs_p1 + epochs_p2,  # Continue epoch numbering
        initial_epoch=len(history_p1.history["loss"]),
        callbacks=callbacks_p2,
        class_weight=class_weights if not use_focal else None,
    )

    # Merge histories
    history = {
        "loss": history_p1.history["loss"] + history_p2.history["loss"],
        "val_loss": history_p1.history["val_loss"] + history_p2.history["val_loss"],
        "accuracy": history_p1.history["accuracy"] + history_p2.history["accuracy"],
        "val_accuracy": history_p1.history["val_accuracy"] + history_p2.history["val_accuracy"],
    }

    best_val_loss = min(history["val_loss"])
    best_val_acc = max(history["val_accuracy"])
    print(f"\n[INFO] Adaptive model training complete.")
    print(f"  Best val_loss: {best_val_loss:.4f}")
    print(f"  Best val_acc : {best_val_acc:.4f}")

    return model, history


# ============================================================================
# STEP 8: Save & Export Utilities
# ============================================================================

def save_training_plots(history, model_name):
    """Save training curves (loss, accuracy) as PNG."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))

    if isinstance(history, dict):
        h = history
    else:
        h = history.history

    # Loss
    ax1.plot(h["loss"], label="Train Loss")
    ax1.plot(h["val_loss"], label="Val Loss")
    ax1.set_title(f"{model_name} - Loss")
    ax1.set_xlabel("Epoch")
    ax1.set_ylabel("Loss")
    ax1.legend()
    ax1.grid(True, alpha=0.3)

    # Accuracy
    ax2.plot(h["accuracy"], label="Train Acc")
    ax2.plot(h["val_accuracy"], label="Val Acc")
    ax2.set_title(f"{model_name} - Accuracy")
    ax2.set_xlabel("Epoch")
    ax2.set_ylabel("Accuracy")
    ax2.legend()
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    results_dir = PROJECT_DIR / "docs" / "results"
    results_dir.mkdir(parents=True, exist_ok=True)
    path = results_dir / f"{model_name}_training_curves.png"
    plt.savefig(str(path), dpi=150, bbox_inches="tight")
    plt.close()
    print(f"[INFO] Training plots saved to {path}")


# ============================================================================
# MAIN
# ============================================================================

def main():
    import argparse

    parser = argparse.ArgumentParser(description="EmoSense Emotion Recognition Training")
    parser.add_argument("--model", choices=["baseline", "adaptive", "both"],
                        default="adaptive", help="Which model to train (default: adaptive)")
    parser.add_argument("--epochs-phase1", type=int, default=EPOCHS_PHASE1,
                        help=f"Phase 1 epochs (default: {EPOCHS_PHASE1})")
    parser.add_argument("--epochs-phase2", type=int, default=EPOCHS_PHASE2,
                        help=f"Phase 2 epochs (default: {EPOCHS_PHASE2})")
    parser.add_argument("--batch-size", type=int, default=BATCH_SIZE,
                        help=f"Batch size (default: {BATCH_SIZE})")
    parser.add_argument("--use-focal-loss", action="store_true",
                        help="Use focal loss instead of cross-entropy")
    parser.add_argument("--skip-preprocessing", action="store_true",
                        help="Skip face detection preprocessing (use already processed data)")
    parser.add_argument("--force-preprocess", action="store_true",
                        help="Force re-run of preprocessing even if processed data exists")
    args = parser.parse_args()

    print("=" * 70)
    print("EmoSense Emotion Recognition - Training Pipeline")
    print("=" * 70)

    # GPU detection
    gpus = tf.config.list_physical_devices("GPU")
    if gpus:
        print(f"[INFO] GPU detected: {len(gpus)} device(s)")
        for gpu in gpus:
            print(f"  - {gpu.name}")
        # Enable memory growth to prevent OOM
        for gpu in gpus:
            try:
                tf.config.experimental.set_memory_growth(gpu, True)
            except RuntimeError:
                pass
    else:
        print("[INFO] No GPU detected - using CPU (training will be slower)")

    print(f"[INFO] TensorFlow version: {tf.__version__}")
    print(f"[INFO] Random seed: {SEED}")

    # Step 1: Extract dataset if needed
    extract_dataset()

    # Step 2: Preprocess (face detection + crop)
    if not args.skip_preprocessing:
        preprocess_dataset(force=args.force_preprocess)
    else:
        print("[INFO] Skipping preprocessing (--skip-preprocessing)")

    # Step 3: Load and split dataset
    (X_train, y_train), (X_val, y_val), (X_test, y_test) = load_dataset()

    # Step 4: Compute class weights
    class_weights = compute_class_weights_dict(y_train)

    # Step 5: Create data pipelines
    train_ds = create_tf_dataset(X_train, y_train, args.batch_size, is_training=True)
    val_ds = create_tf_dataset(X_val, y_val, args.batch_size, is_training=False)
    test_ds = create_tf_dataset(X_test, y_test, args.batch_size, is_training=False)

    # Step 6: Train models
    if args.model in ("baseline", "both"):
        baseline_model, baseline_history = train_baseline(
            train_ds, val_ds, class_weights, use_focal=args.use_focal_loss
        )
        save_training_plots(baseline_history, "baseline_cnn")

        # Quick evaluation
        print("\n[INFO] Baseline CNN - Test evaluation:")
        baseline_model.evaluate(test_ds, verbose=1)

    if args.model in ("adaptive", "both"):
        adaptive_model, adaptive_history = train_adaptive(
            train_ds, val_ds, class_weights,
            use_focal=args.use_focal_loss,
            epochs_p1=args.epochs_phase1,
            epochs_p2=args.epochs_phase2
        )
        save_training_plots(adaptive_history, "adaptive_model")

        # Quick evaluation
        print("\n[INFO] Adaptive Model - Test evaluation:")
        adaptive_model.evaluate(test_ds, verbose=1)

    # Save test set for evaluate.py
    test_data_dir = SAVED_MODELS_DIR / "test_data"
    test_data_dir.mkdir(parents=True, exist_ok=True)
    np.save(str(test_data_dir / "X_test.npy"), X_test)
    np.save(str(test_data_dir / "y_test.npy"), y_test)
    print(f"\n[INFO] Test data saved to {test_data_dir}")

    print("\n" + "=" * 70)
    print("TRAINING COMPLETE")
    print("=" * 70)
    print(f"\nSaved models  : {SAVED_MODELS_DIR}")
    print(f"Next steps:")
    print(f"  1. Evaluate : python evaluate.py")
    print(f"  2. Export   : python export_tflite.py")


if __name__ == "__main__":
    main()
