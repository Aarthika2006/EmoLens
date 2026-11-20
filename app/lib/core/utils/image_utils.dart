import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Utility functions for image preprocessing.
/// MUST match training pipeline: resize 224x224, normalize to [-1, 1].
class ImageUtils {
  ImageUtils._();

  /// Decodes JPEG bytes to an [img.Image].
  static img.Image? decodeJpeg(Uint8List bytes) {
    try {
      return img.decodeJpg(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Crops a face region from the image with a margin.
  ///
  /// [rect] is {left, top, width, height} in image coordinates.
  /// [margin] is the fraction of extra padding (e.g., 0.2 = 20%).
  static img.Image cropFace(
    img.Image image, {
    required int left,
    required int top,
    required int width,
    required int height,
    double margin = 0.2,
  }) {
    final int marginX = (width * margin).round();
    final int marginY = (height * margin).round();

    final int x = math.max(0, left - marginX);
    final int y = math.max(0, top - marginY);
    final int w = math.min(image.width - x, width + 2 * marginX);
    final int h = math.min(image.height - y, height + 2 * marginY);

    return img.copyCrop(image, x: x, y: y, width: w, height: h);
  }

  /// Resizes image to [targetSize] x [targetSize].
  static img.Image resizeSquare(img.Image image, int targetSize) {
    return img.copyResize(image,
        width: targetSize,
        height: targetSize,
        interpolation: img.Interpolation.linear);
  }

  /// Preprocesses a face crop for the TFLite model.
  ///
  /// 1. Resize to 224x224
  /// 2. Normalize pixel values to [-1, 1] using (pixel / 127.5) - 1.0
  ///
  /// Returns a Float32List of shape [1, 224, 224, 3] (NHWC).
  static Float32List preprocessForModel(img.Image faceCrop,
      {int inputSize = 224}) {
    final resized = resizeSquare(faceCrop, inputSize);
    final buffer = Float32List(1 * inputSize * inputSize * 3);

    int idx = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        // Normalize to [-1, 1]: pixel / 127.5 - 1.0
        buffer[idx++] = pixel.r / 127.5 - 1.0;
        buffer[idx++] = pixel.g / 127.5 - 1.0;
        buffer[idx++] = pixel.b / 127.5 - 1.0;
      }
    }
    return buffer;
  }

  /// Converts raw JPEG bytes to a preprocessed Float32List for inference.
  /// Returns null if decoding fails.
  static Float32List? preprocessJpeg(Uint8List jpegBytes,
      {int inputSize = 224}) {
    final decoded = decodeJpeg(jpegBytes);
    if (decoded == null) return null;
    return preprocessForModel(decoded, inputSize: inputSize);
  }

  /// Converts an [img.Image] to JPEG bytes.
  static Uint8List encodeJpeg(img.Image image, {int quality = 90}) {
    return Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }
}
