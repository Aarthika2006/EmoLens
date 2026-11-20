#!/usr/bin/env python3
"""
evaluate.py - EmoSense Model Evaluation & Visualization
========================================================
Evaluates the trained emotion recognition model on the held-out test set.

Generates:
  1. Classification report (accuracy, per-class precision/recall/F1, macro-F1)
  2. Confusion matrix heatmap
  3. ROC curves (one-vs-rest)
  4. Precision-Recall curves
  5. Grad-CAM visualizations (3 samples per class)

All plots saved to: Capstone/docs/results/

Usage:
    python evaluate.py                                    # Evaluate adaptive model
    python evaluate.py --model-path saved_models/baseline_cnn/best_model.keras
    python evaluate.py --model-name baseline_cnn
"""

import os
import sys
import warnings
from pathlib import Path

import numpy as np

# Suppress warnings
os.environ["TF_CPP_MIN_LOG_LEVEL"] = "2"
warnings.filterwarnings("ignore")

import tensorflow as tf
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import (
    classification_report,
    confusion_matrix,
    roc_curve,
    auc,
    precision_recall_curve,
    average_precision_score,
    f1_score,
    accuracy_score
)
from sklearn.preprocessing import label_binarize

# ============================================================================
# CONFIGURATION
# ============================================================================
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent
SAVED_MODELS_DIR = SCRIPT_DIR / "saved_models"
RESULTS_DIR = PROJECT_DIR / "docs" / "results"

CLASS_NAMES = ["Happy", "Neutral", "Sad"]
NUM_CLASSES = len(CLASS_NAMES)
IMG_SIZE = 224


def load_model_and_data(model_path=None, model_name="adaptive_model"):
    """Load the trained model and test data."""
    if model_path is None:
        model_path = SAVED_MODELS_DIR / model_name / "best_model.keras"
    
    model_path = Path(model_path)
    if not model_path.exists():
        print(f"[ERROR] Model not found: {model_path}")
        print(f"  Run train.py first to generate the model.")
        sys.exit(1)

    print(f"[INFO] Loading model: {model_path}")
    model = tf.keras.models.load_model(model_path, compile=False)

    # Load test data
    test_data_dir = SAVED_MODELS_DIR / "test_data"
    X_test = np.load(str(test_data_dir / "X_test.npy"))
    y_test = np.load(str(test_data_dir / "y_test.npy"))

    print(f"[INFO] Test set: {len(X_test)} images")
    return model, X_test, y_test


def preprocess_for_inference(images):
    """
    Apply MobileNetV2 preprocessing: normalize [0,255] → [-1,1].
    
    Formula: output = (input / 127.5) - 1.0
    This must match the preprocessing in train.py and the Flutter app.
    """
    return images.astype(np.float32) / 127.5 - 1.0


def evaluate_model(model, X_test, y_test):
    """Run full evaluation and return metrics."""
    print("\n" + "=" * 60)
    print("MODEL EVALUATION")
    print("=" * 60)

    X_preprocessed = preprocess_for_inference(X_test)
    y_pred_probs = model.predict(X_preprocessed, verbose=1)
    y_pred = np.argmax(y_pred_probs, axis=1)

    # Overall accuracy
    acc = accuracy_score(y_test, y_pred)
    
    # Per-class and macro F1
    macro_f1 = f1_score(y_test, y_pred, average="macro")
    weighted_f1 = f1_score(y_test, y_pred, average="weighted")
    
    # Classification report
    report = classification_report(y_test, y_pred, target_names=CLASS_NAMES, digits=4)
    
    print(f"\n{'='*50}")
    print(f"  Overall Accuracy : {acc:.4f} ({acc*100:.1f}%)")
    print(f"  Macro F1 (PRIMARY): {macro_f1:.4f}")
    print(f"  Weighted F1       : {weighted_f1:.4f}")
    print(f"{'='*50}")
    print(f"\nClassification Report:\n{report}")

    return y_pred, y_pred_probs, {
        "accuracy": acc,
        "macro_f1": macro_f1,
        "weighted_f1": weighted_f1,
        "report": report
    }


def plot_confusion_matrix(y_test, y_pred, save_dir):
    """Generate and save confusion matrix heatmap."""
    cm = confusion_matrix(y_test, y_pred)
    cm_normalized = cm.astype("float") / cm.sum(axis=1, keepdims=True)

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))

    # Raw counts
    sns.heatmap(cm, annot=True, fmt="d", cmap="Blues", xticklabels=CLASS_NAMES,
                yticklabels=CLASS_NAMES, ax=ax1, cbar_kws={"shrink": 0.8})
    ax1.set_title("Confusion Matrix (Counts)", fontsize=14)
    ax1.set_xlabel("Predicted", fontsize=12)
    ax1.set_ylabel("Actual", fontsize=12)

    # Normalized (percentages)
    sns.heatmap(cm_normalized, annot=True, fmt=".2%", cmap="Blues", xticklabels=CLASS_NAMES,
                yticklabels=CLASS_NAMES, ax=ax2, cbar_kws={"shrink": 0.8})
    ax2.set_title("Confusion Matrix (Normalized)", fontsize=14)
    ax2.set_xlabel("Predicted", fontsize=12)
    ax2.set_ylabel("Actual", fontsize=12)

    plt.tight_layout()
    path = save_dir / "confusion_matrix.png"
    plt.savefig(str(path), dpi=150, bbox_inches="tight")
    plt.close()
    print(f"[INFO] Confusion matrix saved to {path}")


def plot_roc_curves(y_test, y_pred_probs, save_dir):
    """Generate and save ROC curves (one-vs-rest)."""
    y_test_bin = label_binarize(y_test, classes=list(range(NUM_CLASSES)))

    fig, ax = plt.subplots(figsize=(8, 6))
    colors = ["#2ecc71", "#3498db", "#e74c3c"]

    for i, (name, color) in enumerate(zip(CLASS_NAMES, colors)):
        fpr, tpr, _ = roc_curve(y_test_bin[:, i], y_pred_probs[:, i])
        roc_auc = auc(fpr, tpr)
        ax.plot(fpr, tpr, color=color, lw=2, label=f"{name} (AUC = {roc_auc:.3f})")

    # Micro-average
    fpr_micro, tpr_micro, _ = roc_curve(y_test_bin.ravel(), y_pred_probs.ravel())
    roc_auc_micro = auc(fpr_micro, tpr_micro)
    ax.plot(fpr_micro, tpr_micro, color="navy", lw=2, linestyle="--",
            label=f"Micro-avg (AUC = {roc_auc_micro:.3f})")

    ax.plot([0, 1], [0, 1], "k--", lw=1, alpha=0.5)
    ax.set_xlim([0, 1])
    ax.set_ylim([0, 1.05])
    ax.set_xlabel("False Positive Rate", fontsize=12)
    ax.set_ylabel("True Positive Rate", fontsize=12)
    ax.set_title("ROC Curves (One-vs-Rest)", fontsize=14)
    ax.legend(loc="lower right", fontsize=10)
    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    path = save_dir / "roc_curves.png"
    plt.savefig(str(path), dpi=150, bbox_inches="tight")
    plt.close()
    print(f"[INFO] ROC curves saved to {path}")


def plot_pr_curves(y_test, y_pred_probs, save_dir):
    """Generate and save Precision-Recall curves."""
    y_test_bin = label_binarize(y_test, classes=list(range(NUM_CLASSES)))

    fig, ax = plt.subplots(figsize=(8, 6))
    colors = ["#2ecc71", "#3498db", "#e74c3c"]

    for i, (name, color) in enumerate(zip(CLASS_NAMES, colors)):
        precision, recall, _ = precision_recall_curve(y_test_bin[:, i], y_pred_probs[:, i])
        ap = average_precision_score(y_test_bin[:, i], y_pred_probs[:, i])
        ax.plot(recall, precision, color=color, lw=2, label=f"{name} (AP = {ap:.3f})")

    ax.set_xlim([0, 1])
    ax.set_ylim([0, 1.05])
    ax.set_xlabel("Recall", fontsize=12)
    ax.set_ylabel("Precision", fontsize=12)
    ax.set_title("Precision-Recall Curves", fontsize=14)
    ax.legend(loc="lower left", fontsize=10)
    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    path = save_dir / "precision_recall_curves.png"
    plt.savefig(str(path), dpi=150, bbox_inches="tight")
    plt.close()
    print(f"[INFO] PR curves saved to {path}")


def grad_cam(model, image, class_index, last_conv_layer_name=None):
    """
    Compute Grad-CAM heatmap for a given image and class.
    
    Uses tf-keras-vis for robust Grad-CAM computation.
    Falls back to manual implementation if tf-keras-vis is unavailable.
    
    Args:
        model: Trained Keras model
        image: Preprocessed image (float32, [-1, 1]), shape (224, 224, 3)
        class_index: Class index to visualize
        last_conv_layer_name: Name of the last conv layer (auto-detected if None)
    
    Returns:
        Heatmap as numpy array, shape (224, 224), values in [0, 1].
    """
    try:
        from tf_keras_vis.gradcam import Gradcam
        from tf_keras_vis.utils.scores import CategoricalScore

        gradcam = Gradcam(model, clone=True)
        score = CategoricalScore([class_index])
        cam = gradcam(score, np.expand_dims(image, 0), penultimate_layer=-1)
        heatmap = cam[0]
        return heatmap
    except Exception:
        pass

    # Manual Grad-CAM fallback
    if last_conv_layer_name is None:
        # Find last Conv2D layer
        for layer in reversed(model.layers):
            if isinstance(layer, tf.keras.layers.Conv2D):
                last_conv_layer_name = layer.name
                break
            # For functional models with nested models
            if hasattr(layer, "layers"):
                for sub_layer in reversed(layer.layers):
                    if isinstance(sub_layer, tf.keras.layers.Conv2D):
                        last_conv_layer_name = layer.name
                        break
                if last_conv_layer_name:
                    break

    if last_conv_layer_name is None:
        return np.zeros((IMG_SIZE, IMG_SIZE))

    try:
        grad_model = tf.keras.Model(
            inputs=model.input,
            outputs=[model.get_layer(last_conv_layer_name).output, model.output]
        )
    except ValueError:
        # Layer might be nested
        return np.zeros((IMG_SIZE, IMG_SIZE))

    with tf.GradientTape() as tape:
        conv_output, predictions = grad_model(np.expand_dims(image, 0))
        loss = predictions[:, class_index]

    grads = tape.gradient(loss, conv_output)
    if grads is None:
        return np.zeros((IMG_SIZE, IMG_SIZE))

    pooled_grads = tf.reduce_mean(grads, axis=(0, 1, 2))
    conv_output = conv_output[0]
    heatmap = conv_output @ pooled_grads[..., tf.newaxis]
    heatmap = tf.squeeze(heatmap)
    heatmap = tf.maximum(heatmap, 0) / (tf.math.reduce_max(heatmap) + 1e-8)
    heatmap = heatmap.numpy()
    heatmap = np.array(
        tf.image.resize(heatmap[..., np.newaxis], (IMG_SIZE, IMG_SIZE))
    ).squeeze()

    return heatmap


def plot_gradcam_samples(model, X_test, y_test, save_dir, samples_per_class=3):
    """Generate Grad-CAM visualizations for sample images from each class."""
    print("[INFO] Generating Grad-CAM visualizations...")
    X_preprocessed = preprocess_for_inference(X_test)

    fig, axes = plt.subplots(NUM_CLASSES, samples_per_class * 2, 
                              figsize=(4 * samples_per_class * 2, 4 * NUM_CLASSES))

    for class_idx, class_name in enumerate(CLASS_NAMES):
        # Get indices for this class
        class_mask = y_test == class_idx
        class_indices = np.where(class_mask)[0]
        
        if len(class_indices) == 0:
            continue

        # Sample random images from this class
        np.random.seed(42)
        sample_indices = np.random.choice(
            class_indices, size=min(samples_per_class, len(class_indices)), replace=False
        )

        for j, idx in enumerate(sample_indices):
            img_preprocessed = X_preprocessed[idx]
            img_original = X_test[idx]  # uint8 for display

            # Compute Grad-CAM
            heatmap = grad_cam(model, img_preprocessed, class_idx)

            # Original image
            ax_orig = axes[class_idx, j * 2] if NUM_CLASSES > 1 else axes[j * 2]
            ax_orig.imshow(img_original)
            ax_orig.set_title(f"{class_name} (Original)", fontsize=10)
            ax_orig.axis("off")

            # Grad-CAM overlay
            ax_cam = axes[class_idx, j * 2 + 1] if NUM_CLASSES > 1 else axes[j * 2 + 1]
            ax_cam.imshow(img_original)
            ax_cam.imshow(heatmap, cmap="jet", alpha=0.4)
            ax_cam.set_title(f"{class_name} (Grad-CAM)", fontsize=10)
            ax_cam.axis("off")

    plt.suptitle("Grad-CAM Attention Visualizations", fontsize=16, fontweight="bold")
    plt.tight_layout()
    path = save_dir / "gradcam_visualizations.png"
    plt.savefig(str(path), dpi=150, bbox_inches="tight")
    plt.close()
    print(f"[INFO] Grad-CAM visualizations saved to {path}")


def print_summary_table(metrics):
    """Print a formatted summary table."""
    print("\n" + "=" * 60)
    print("EVALUATION SUMMARY")
    print("=" * 60)
    print(f"{'Metric':<25} {'Value':>10}")
    print("-" * 36)
    print(f"{'Overall Accuracy':<25} {metrics['accuracy']:>10.4f}")
    print(f"{'Macro F1 (PRIMARY)':<25} {metrics['macro_f1']:>10.4f}")
    print(f"{'Weighted F1':<25} {metrics['weighted_f1']:>10.4f}")
    print("-" * 36)
    print(f"\nFull classification report:\n{metrics['report']}")
    print("=" * 60)


def main():
    import argparse

    parser = argparse.ArgumentParser(description="EmoSense Model Evaluation")
    parser.add_argument("--model-path", type=str, default=None,
                        help="Path to the saved .keras model file")
    parser.add_argument("--model-name", type=str, default="adaptive_model",
                        help="Model name (looks for saved_models/<name>/best_model.keras)")
    args = parser.parse_args()

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    # Load model and test data
    model, X_test, y_test = load_model_and_data(
        model_path=args.model_path,
        model_name=args.model_name
    )

    # Run evaluation
    y_pred, y_pred_probs, metrics = evaluate_model(model, X_test, y_test)

    # Generate all plots
    plot_confusion_matrix(y_test, y_pred, RESULTS_DIR)
    plot_roc_curves(y_test, y_pred_probs, RESULTS_DIR)
    plot_pr_curves(y_test, y_pred_probs, RESULTS_DIR)
    plot_gradcam_samples(model, X_test, y_test, RESULTS_DIR)

    # Print summary
    print_summary_table(metrics)

    print(f"\n[INFO] All evaluation results saved to: {RESULTS_DIR}")
    print(f"[INFO] Files generated:")
    for f in sorted(RESULTS_DIR.glob("*.png")):
        print(f"  - {f.name}")


if __name__ == "__main__":
    main()
