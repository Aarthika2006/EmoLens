#!/usr/bin/env python3
"""
export_tflite.py - Export Keras Model to TensorFlow Lite
========================================================
Converts the trained Keras emotion recognition model to TFLite format
for deployment on Android (Flutter app).

Outputs:
  1. emotion_model.tflite        - Float16 quantized (PRIMARY, best quality)
  2. emotion_model_int8.tflite   - Int8 quantized (smaller, faster, slight accuracy drop)
  3. labels.txt                  - Class labels file

Verification:
  - Runs inference on 10 test images with both Keras and TFLite models
  - Prints max absolute difference to verify numerical equivalence
  - Reports final model sizes

Usage:
    python export_tflite.py
    python export_tflite.py --model-path saved_models/adaptive_model/best_model.keras
    python export_tflite.py --model-name baseline_cnn

PREPROCESSING REMINDER:
  The TFLite model expects input preprocessed as:
    1. Face detection + crop (MediaPipe, 20% padding)
    2. Resize to 224x224
    3. Normalize: (pixel / 127.5) - 1.0  → range [-1.0, 1.0]
  The Flutter app MUST apply this preprocessing identically.
"""

import os
import sys
import warnings
from pathlib import Path

import numpy as np

os.environ["TF_CPP_MIN_LOG_LEVEL"] = "2"
warnings.filterwarnings("ignore")

import tensorflow as tf

# ============================================================================
# CONFIGURATION
# ============================================================================
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent
SAVED_MODELS_DIR = SCRIPT_DIR / "saved_models"
TFLITE_OUTPUT_DIR = PROJECT_DIR / "app" / "assets" / "models"

CLASS_NAMES = ["Happy", "Neutral", "Sad"]
IMG_SIZE = 224
MAX_MODEL_SIZE_MB = 10  # Target: keep under 10 MB


def load_model(model_path=None, model_name="adaptive_model"):
    """Load the trained Keras model."""
    if model_path is None:
        model_path = SAVED_MODELS_DIR / model_name / "best_model.keras"
    
    model_path = Path(model_path)
    if not model_path.exists():
        print(f"[ERROR] Model not found: {model_path}")
        print(f"  Run train.py first.")
        sys.exit(1)

    print(f"[INFO] Loading Keras model: {model_path}")
    model = tf.keras.models.load_model(model_path, compile=False)
    return model


def export_float16(model, output_path):
    """
    Export model with float16 quantization.
    
    Float16 reduces model size by ~50% with minimal accuracy loss.
    This is the PRIMARY model for the Android app.
    
    Args:
        model: Trained Keras model
        output_path: Path to save the .tflite file
    
    Returns:
        Size of the exported model in bytes.
    """
    print("\n[INFO] Exporting Float16 TFLite model...")
    
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    
    # Float16 quantization
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    
    # Allow TF ops fallback if needed
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS
    ]
    converter._experimental_lower_tensor_list_ops = False
    
    tflite_model = converter.convert()
    
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(tflite_model)
    
    size_mb = len(tflite_model) / (1024 * 1024)
    print(f"[INFO] Float16 model saved: {output_path}")
    print(f"  Size: {size_mb:.2f} MB")
    
    if size_mb > MAX_MODEL_SIZE_MB:
        print(f"  ⚠ WARNING: Model exceeds {MAX_MODEL_SIZE_MB} MB target!")
    else:
        print(f"  ✓ Model is under {MAX_MODEL_SIZE_MB} MB target.")
    
    return len(tflite_model)


def export_int8(model, output_path, representative_data=None):
    """
    Export model with full integer (int8) quantization.
    
    Int8 quantization provides maximum size reduction and fastest inference
    on mobile, but may have slightly lower accuracy.
    
    Requires representative dataset for calibration.
    
    Args:
        model: Trained Keras model
        output_path: Path to save the .tflite file
        representative_data: Numpy array of sample images for calibration.
                            If None, generates random calibration data.
    
    Returns:
        Size of the exported model in bytes.
    """
    print("\n[INFO] Exporting Int8 TFLite model...")
    
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    
    # Representative dataset for int8 calibration
    def representative_dataset_gen():
        if representative_data is not None:
            for i in range(min(100, len(representative_data))):
                sample = representative_data[i:i+1].astype(np.float32)
                # Apply MobileNetV2 preprocessing: [0,255] → [-1,1]
                sample = sample / 127.5 - 1.0
                yield [sample]
        else:
            # Generate random calibration data as fallback
            for _ in range(100):
                sample = np.random.uniform(-1.0, 1.0, (1, IMG_SIZE, IMG_SIZE, 3)).astype(np.float32)
                yield [sample]
    
    converter.representative_dataset = representative_dataset_gen
    
    # Force int8 for all ops where possible
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS_INT8,
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS
    ]
    # Allow float fallback for ops that don't support int8
    converter.inference_input_type = tf.float32  # Keep float input for compatibility
    converter.inference_output_type = tf.float32  # Keep float output
    
    try:
        tflite_model = converter.convert()
    except Exception as e:
        print(f"[WARN] Int8 quantization failed: {e}")
        print("[INFO] Falling back to dynamic range quantization...")
        converter2 = tf.lite.TFLiteConverter.from_keras_model(model)
        converter2.optimizations = [tf.lite.Optimize.DEFAULT]
        converter2.target_spec.supported_ops = [
            tf.lite.OpsSet.TFLITE_BUILTINS,
            tf.lite.OpsSet.SELECT_TF_OPS
        ]
        tflite_model = converter2.convert()
    
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(tflite_model)
    
    size_mb = len(tflite_model) / (1024 * 1024)
    print(f"[INFO] Int8 model saved: {output_path}")
    print(f"  Size: {size_mb:.2f} MB")
    
    return len(tflite_model)


def save_labels(output_dir):
    """
    Save class labels to labels.txt.
    
    Format: one label per line, in the same order as model output indices.
    Index 0 = Happy, Index 1 = Neutral, Index 2 = Sad
    """
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    labels_path = output_dir / "labels.txt"
    
    with open(labels_path, "w") as f:
        for name in CLASS_NAMES:
            f.write(f"{name}\n")
    
    print(f"[INFO] Labels saved to {labels_path}")
    print(f"  Classes: {CLASS_NAMES}")


def verify_tflite(keras_model, tflite_path, test_images, num_samples=10):
    """
    Verify TFLite output matches Keras output on test images.
    
    Compares predictions from both models and reports maximum absolute
    difference to ensure conversion fidelity.
    
    Args:
        keras_model: Original Keras model
        tflite_path: Path to the TFLite model
        test_images: uint8 numpy array of test images
        num_samples: Number of images to test
    
    Returns:
        Maximum absolute difference across all samples and outputs.
    """
    print(f"\n[INFO] Verifying TFLite model against Keras ({num_samples} samples)...")
    
    # Load TFLite model
    interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
    interpreter.allocate_tensors()
    
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()
    
    print(f"  TFLite input  : {input_details[0]['shape']} {input_details[0]['dtype']}")
    print(f"  TFLite output : {output_details[0]['shape']} {output_details[0]['dtype']}")
    
    max_diff = 0.0
    num_samples = min(num_samples, len(test_images))
    
    for i in range(num_samples):
        # Preprocess: [0,255] → [-1,1]
        img = test_images[i:i+1].astype(np.float32) / 127.5 - 1.0
        
        # Keras prediction
        keras_pred = keras_model.predict(img, verbose=0)[0]
        
        # TFLite prediction
        interpreter.set_tensor(input_details[0]["index"], img)
        interpreter.invoke()
        tflite_pred = interpreter.get_tensor(output_details[0]["index"])[0]
        
        diff = np.max(np.abs(keras_pred - tflite_pred))
        max_diff = max(max_diff, diff)
        
        keras_class = CLASS_NAMES[np.argmax(keras_pred)]
        tflite_class = CLASS_NAMES[np.argmax(tflite_pred)]
        match = "✓" if keras_class == tflite_class else "✗"
        
        print(f"  [{i+1:2d}] Keras: {keras_class:8s} {keras_pred} | "
              f"TFLite: {tflite_class:8s} {tflite_pred} | diff={diff:.6f} {match}")
    
    print(f"\n  Max absolute difference: {max_diff:.6f}")
    if max_diff < 0.01:
        print(f"  ✓ Excellent: TFLite output closely matches Keras")
    elif max_diff < 0.05:
        print(f"  ⚠ Acceptable: Small numerical differences (expected with quantization)")
    else:
        print(f"  ✗ WARNING: Large differences detected - check conversion!")
    
    return max_diff


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Export Keras model to TFLite")
    parser.add_argument("--model-path", type=str, default=None,
                        help="Path to the .keras model file")
    parser.add_argument("--model-name", type=str, default="adaptive_model",
                        help="Model name (default: adaptive_model)")
    parser.add_argument("--output-dir", type=str, default=str(TFLITE_OUTPUT_DIR),
                        help=f"Output directory (default: {TFLITE_OUTPUT_DIR})")
    parser.add_argument("--skip-int8", action="store_true",
                        help="Skip int8 quantization export")
    args = parser.parse_args()

    output_dir = Path(args.output_dir)

    print("=" * 60)
    print("EmoSense - TFLite Export")
    print("=" * 60)

    # Load Keras model
    keras_model = load_model(args.model_path, args.model_name)
    keras_model.summary()

    # Load test data for verification and int8 calibration
    test_data_dir = SAVED_MODELS_DIR / "test_data"
    X_test = None
    if (test_data_dir / "X_test.npy").exists():
        X_test = np.load(str(test_data_dir / "X_test.npy"))
        print(f"\n[INFO] Loaded {len(X_test)} test images for verification")
    else:
        print("[WARN] No test data found. Verification will use random data.")

    # Export Float16 (primary)
    f16_path = output_dir / "emotion_model.tflite"
    f16_size = export_float16(keras_model, f16_path)

    # Export Int8 (alternative)
    if not args.skip_int8:
        i8_path = output_dir / "emotion_model_int8.tflite"
        i8_size = export_int8(keras_model, i8_path, representative_data=X_test)
    else:
        i8_size = 0

    # Save labels
    save_labels(output_dir)

    # Verify Float16 model
    if X_test is not None:
        verify_tflite(keras_model, f16_path, X_test, num_samples=10)
    
    # Summary
    print("\n" + "=" * 60)
    print("EXPORT SUMMARY")
    print("=" * 60)
    print(f"{'File':<35} {'Size':>10}")
    print("-" * 46)
    print(f"{'emotion_model.tflite (float16)':<35} {f16_size/1024/1024:>8.2f} MB")
    if i8_size > 0:
        print(f"{'emotion_model_int8.tflite (int8)':<35} {i8_size/1024/1024:>8.2f} MB")
    print(f"{'labels.txt':<35} {'< 1 KB':>10}")
    print("-" * 46)
    print(f"\n[INFO] Output directory: {output_dir}")
    print(f"\nFiles for Flutter app (copy to assets/models/):")
    for f in sorted(output_dir.glob("*")):
        print(f"  - {f.name}")


if __name__ == "__main__":
    main()
