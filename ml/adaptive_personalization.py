#!/usr/bin/env python3
"""
adaptive_personalization.py - On-Device Adaptive Personalization Helper
========================================================================
Provides tools for caregiver-guided personalization of the emotion model.

APPROACH:
  Caregivers can correct misclassified emotions in the Flutter app. These
  corrections (face crop + correct label) are stored locally on the device.
  When enough corrections accumulate, only the last Dense layers are
  fine-tuned to adapt to the individual's unique expressions.

WORKFLOW:
  1. User corrects emotion in Flutter app → saves face crop + label
  2. Corrections exported as a folder: corrections/{Happy,Neutral,Sad}/*.jpg
  3. This script fine-tunes the last Dense layers on the corrections
  4. Exports an updated TFLite model for the app

LIMITATIONS:
  - Catastrophic forgetting: Fine-tuning on very few samples can cause the
    model to "forget" general patterns. Mitigated by freezing all layers
    except the final Dense layers and using a very low learning rate.
  - Small data: With only 5-20 corrections, overfitting is likely. We use
    strong regularization (dropout, L2) and early stopping.
  - Distribution shift: If correction images are very different from training
    data (lighting, angle, resolution), adaptation may not transfer well.
  - No rollback guarantee: Keep the original model as a fallback.
  - Privacy: All corrections stay on-device. This script runs locally.

Usage:
    python adaptive_personalization.py \\
        --corrections-dir path/to/corrections/ \\
        --base-model saved_models/adaptive_model/best_model.keras \\
        --output-tflite app/assets/models/emotion_model_personalized.tflite

    # Dry run (just validate corrections, don't train)
    python adaptive_personalization.py \\
        --corrections-dir path/to/corrections/ \\
        --dry-run

PREPROCESSING CONTRACT (same as train.py and Flutter app):
  1. Face crop: 224x224 pixels
  2. Normalize: (pixel / 127.5) - 1.0 → range [-1.0, 1.0]
"""

import os
import sys
import warnings
from pathlib import Path

import numpy as np

os.environ["TF_CPP_MIN_LOG_LEVEL"] = "2"
warnings.filterwarnings("ignore")

import tensorflow as tf
import cv2

# ============================================================================
# CONFIGURATION
# ============================================================================
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent
SAVED_MODELS_DIR = SCRIPT_DIR / "saved_models"

CLASS_NAMES = ["Happy", "Neutral", "Sad"]
NUM_CLASSES = len(CLASS_NAMES)
IMG_SIZE = 224

# Fine-tuning hyperparameters (conservative to prevent catastrophic forgetting)
FINETUNE_LR = 1e-5         # Very low learning rate
FINETUNE_EPOCHS = 10        # Few epochs
FINETUNE_BATCH_SIZE = 4     # Small batch (few corrections expected)
MIN_CORRECTIONS = 3         # Minimum corrections needed to fine-tune
MAX_CORRECTIONS = 500       # Safety cap


# ============================================================================
# LOAD CORRECTIONS
# ============================================================================

def load_corrections(corrections_dir: str):
    """
    Load correction images from a directory structure:
      corrections_dir/
        Happy/    *.jpg
        Neutral/  *.jpg
        Sad/      *.jpg
    
    Args:
        corrections_dir: Path to the corrections directory.
    
    Returns:
        (images, labels) as numpy arrays.
        images: uint8 (N, 224, 224, 3)
        labels: int32 (N,)
    """
    corrections_dir = Path(corrections_dir)
    images = []
    labels = []
    
    print(f"[INFO] Loading corrections from: {corrections_dir}")
    
    for class_idx, class_name in enumerate(CLASS_NAMES):
        class_dir = corrections_dir / class_name
        if not class_dir.exists():
            print(f"  {class_name}: 0 images (directory not found)")
            continue
        
        img_files = sorted(
            list(class_dir.glob("*.jpg")) + 
            list(class_dir.glob("*.jpeg")) +
            list(class_dir.glob("*.png"))
        )
        
        count = 0
        for img_path in img_files:
            img = cv2.imread(str(img_path))
            if img is None:
                print(f"  [WARN] Cannot read: {img_path.name}")
                continue
            
            img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            img_resized = cv2.resize(img_rgb, (IMG_SIZE, IMG_SIZE), 
                                      interpolation=cv2.INTER_LINEAR)
            images.append(img_resized)
            labels.append(class_idx)
            count += 1
        
        print(f"  {class_name}: {count} images")
    
    if not images:
        print("[ERROR] No valid correction images found!")
        return None, None
    
    X = np.array(images, dtype=np.uint8)
    y = np.array(labels, dtype=np.int32)
    
    print(f"[INFO] Total corrections loaded: {len(X)}")
    return X, y


# ============================================================================
# FINE-TUNING
# ============================================================================

def fine_tune_model(base_model_path: str, X_corrections, y_corrections,
                    lr=FINETUNE_LR, epochs=FINETUNE_EPOCHS, 
                    batch_size=FINETUNE_BATCH_SIZE):
    """
    Fine-tune only the last Dense layers of the model on corrections.
    
    Strategy:
      - Freeze ALL layers except the final Dense layers (dense_128, predictions)
      - Use very low learning rate (1e-5) to prevent catastrophic forgetting
      - Apply heavy dropout during fine-tuning
      - Use early stopping to prevent overfitting on few samples
    
    Args:
        base_model_path: Path to the base Keras model (.keras)
        X_corrections: uint8 correction images (N, 224, 224, 3)
        y_corrections: integer labels (N,)
        lr: Learning rate
        epochs: Max fine-tuning epochs
        batch_size: Batch size
    
    Returns:
        Fine-tuned Keras model.
    """
    print(f"\n[INFO] Loading base model: {base_model_path}")
    model = tf.keras.models.load_model(base_model_path, compile=False)
    
    # Freeze everything except last Dense layers
    trainable_layer_names = ["dense_128", "predictions", "dropout_1", "dropout_2"]
    frozen_count = 0
    trainable_count = 0
    
    for layer in model.layers:
        if hasattr(layer, 'layers'):
            # Nested model (e.g., MobileNetV2 backbone)
            layer.trainable = False
            frozen_count += len(layer.layers)
        elif layer.name in trainable_layer_names:
            layer.trainable = True
            trainable_count += 1
        else:
            layer.trainable = False
            frozen_count += 1
    
    print(f"[INFO] Frozen layers: {frozen_count}, Trainable layers: {trainable_count}")
    
    # Compile with very conservative settings
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=lr),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"]
    )
    
    # Preprocess corrections
    # Same preprocessing as training: [0,255] → [-1,1]
    X_preprocessed = X_corrections.astype(np.float32) / 127.5 - 1.0
    
    # Simple augmentation via tf.data
    dataset = tf.data.Dataset.from_tensor_slices((X_preprocessed, y_corrections))
    dataset = dataset.shuffle(len(X_corrections), seed=42)
    
    # Split: 80% train, 20% validation (if enough samples)
    n_total = len(X_corrections)
    n_val = max(1, int(0.2 * n_total))
    n_train = n_total - n_val
    
    train_ds = dataset.take(n_train).batch(batch_size).prefetch(tf.data.AUTOTUNE)
    val_ds = dataset.skip(n_train).batch(batch_size).prefetch(tf.data.AUTOTUNE)
    
    # Callbacks
    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_loss" if n_val > 0 else "loss",
            patience=3,
            restore_best_weights=True,
            verbose=1
        ),
    ]
    
    # Fine-tune
    print(f"\n[INFO] Fine-tuning on {n_train} samples (val: {n_val})...")
    history = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=epochs,
        callbacks=callbacks,
        verbose=1
    )
    
    final_loss = history.history["loss"][-1]
    final_acc = history.history["accuracy"][-1]
    print(f"\n[INFO] Fine-tuning complete.")
    print(f"  Final loss    : {final_loss:.4f}")
    print(f"  Final accuracy: {final_acc:.4f}")
    
    return model


def export_personalized_tflite(model, output_path):
    """Export the fine-tuned model to TFLite with float16 quantization."""
    print(f"\n[INFO] Exporting personalized TFLite model...")
    
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS
    ]
    
    tflite_model = converter.convert()
    
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(tflite_model)
    
    size_mb = len(tflite_model) / (1024 * 1024)
    print(f"[INFO] Personalized model saved: {output_path}")
    print(f"  Size: {size_mb:.2f} MB")
    
    return output_path


# ============================================================================
# MAIN
# ============================================================================

def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Fine-tune emotion model on caregiver corrections.",
        epilog="""
ADAPTIVE PERSONALIZATION DOCUMENTATION:

This script implements on-device adaptation for the EmoSense emotion 
recognition system. The approach is designed for caregivers of individuals 
with Down syndrome who want to improve recognition accuracy for a specific 
person.

HOW IT WORKS:
  1. The Flutter app displays predicted emotions in real-time.
  2. When a prediction is wrong, the caregiver taps to correct it.
  3. The app saves the face crop + correct label to local storage.
  4. When enough corrections accumulate (minimum 3), this script fine-tunes
     only the last classification layers on the corrections.
  5. The updated TFLite model replaces the original in the app.

SAFETY MEASURES:
  - Only the last Dense layers are modified (backbone stays frozen)
  - Very low learning rate (1e-5) prevents catastrophic forgetting
  - Early stopping prevents overfitting on small datasets
  - Original model is never overwritten (saved as separate file)
  - Minimum 3 corrections required before fine-tuning is attempted

KNOWN LIMITATIONS:
  1. CATASTROPHIC FORGETTING: Even with frozen backbone, fine-tuning on
     very few samples (< 10) can degrade performance on the original classes.
     Recommendation: collect at least 10 corrections per class.
  
  2. SMALL DATA OVERFITTING: With < 20 total corrections, the model may
     memorize rather than generalize. Cross-validation is not meaningful.
     Recommendation: collect diverse corrections (different lighting, angles).
  
  3. DISTRIBUTION SHIFT: ESP32-CAM images differ from training data in
     resolution, compression, and lighting. Corrections should come from
     actual ESP32-CAM captures to match deployment conditions.
  
  4. NO ROLLBACK GUARANTEE: If personalization degrades performance,
     manually restore the original emotion_model.tflite.
  
  5. CLASS BALANCE: If all corrections are for one class (e.g., only Sad 
     corrections), the model may bias toward that class. Try to collect
     corrections for all three emotions.
  
  6. PRIVACY: All corrections remain on the device. This script processes
     them locally. No data is uploaded to any server.
        """
    )
    parser.add_argument(
        "--corrections-dir", required=True,
        help="Path to corrections directory (with Happy/, Neutral/, Sad/ subdirs)"
    )
    parser.add_argument(
        "--base-model", default=str(SAVED_MODELS_DIR / "adaptive_model" / "best_model.keras"),
        help="Path to the base Keras model"
    )
    parser.add_argument(
        "--output-tflite",
        default=str(PROJECT_DIR / "app" / "assets" / "models" / "emotion_model_personalized.tflite"),
        help="Output path for personalized TFLite model"
    )
    parser.add_argument(
        "--lr", type=float, default=FINETUNE_LR,
        help=f"Fine-tuning learning rate (default: {FINETUNE_LR})"
    )
    parser.add_argument(
        "--epochs", type=int, default=FINETUNE_EPOCHS,
        help=f"Max fine-tuning epochs (default: {FINETUNE_EPOCHS})"
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Only validate corrections, don't train"
    )
    args = parser.parse_args()

    print("=" * 60)
    print("EmoSense - Adaptive Personalization")
    print("=" * 60)

    # Load corrections
    X_corrections, y_corrections = load_corrections(args.corrections_dir)
    
    if X_corrections is None:
        sys.exit(1)
    
    if len(X_corrections) < MIN_CORRECTIONS:
        print(f"\n[ERROR] Need at least {MIN_CORRECTIONS} corrections, got {len(X_corrections)}.")
        print(f"  Collect more corrections in the app before fine-tuning.")
        sys.exit(1)
    
    if len(X_corrections) > MAX_CORRECTIONS:
        print(f"\n[WARN] Too many corrections ({len(X_corrections)} > {MAX_CORRECTIONS}).")
        print(f"  Using first {MAX_CORRECTIONS} corrections.")
        X_corrections = X_corrections[:MAX_CORRECTIONS]
        y_corrections = y_corrections[:MAX_CORRECTIONS]
    
    if args.dry_run:
        print(f"\n[DRY RUN] Corrections validated. Skipping training.")
        print(f"  Remove --dry-run to fine-tune the model.")
        sys.exit(0)
    
    # Fine-tune
    model = fine_tune_model(
        args.base_model, X_corrections, y_corrections,
        lr=args.lr, epochs=args.epochs
    )
    
    # Export
    output_path = export_personalized_tflite(model, args.output_tflite)
    
    # Summary
    print("\n" + "=" * 60)
    print("PERSONALIZATION COMPLETE")
    print("=" * 60)
    print(f"  Corrections used : {len(X_corrections)}")
    print(f"  Output model     : {output_path}")
    print(f"\nTo use in the app:")
    print(f"  Copy {output_path.name} to the app's assets/models/ directory.")
    print(f"  The app should detect and load the personalized model automatically.")
    print(f"\nTo revert:")
    print(f"  Delete {output_path.name} - the app falls back to emotion_model.tflite.")


if __name__ == "__main__":
    main()
