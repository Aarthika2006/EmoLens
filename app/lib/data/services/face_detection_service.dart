import 'dart:io';
import 'dart:typed_data';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import '../../core/constants/app_constants.dart';
import '../../core/utils/image_utils.dart';

/// Result of face detection on a frame.
class FaceDetectionResult {
  /// The cropped and preprocessed face image (224x224).
  final img.Image? faceCrop;

  /// The face bounding box in the original image coordinates.
  final FaceBoundingBox? boundingBox;

  /// Whether a face was detected.
  final bool faceDetected;

  /// The original image dimensions for overlay scaling.
  final int imageWidth;
  final int imageHeight;

  const FaceDetectionResult({
    this.faceCrop,
    this.boundingBox,
    required this.faceDetected,
    required this.imageWidth,
    required this.imageHeight,
  });
}

/// Bounding box for face overlay drawing.
class FaceBoundingBox {
  final double left;
  final double top;
  final double width;
  final double height;

  const FaceBoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

/// Service for detecting faces in JPEG frames using Google ML Kit.
class FaceDetectionService {
  FaceDetector? _faceDetector;

  FaceDetector get _detector {
    _faceDetector ??= FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: false,
        enableLandmarks: false,
        enableContours: false,
        enableTracking: false,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.15,
      ),
    );
    return _faceDetector!;
  }

  /// Detects faces in a JPEG frame and returns the largest face crop.
  ///
  /// The face is cropped with [AppConstants.faceCropMargin] padding,
  /// then resized to 224x224 (but NOT normalized — that's done in
  /// the classifier to keep concerns separate).
  Future<FaceDetectionResult> detectFace(Uint8List jpegBytes) async {
    // Decode image for dimensions and cropping
    final decoded = ImageUtils.decodeJpeg(jpegBytes);
    if (decoded == null) {
      return FaceDetectionResult(
        faceDetected: false,
        imageWidth: 0,
        imageHeight: 0,
      );
    }

    try {
      // Save frame to temporary file for ML Kit processing
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/live_frame.jpg');
      await tempFile.writeAsBytes(jpegBytes, flush: true);

      final inputImage = InputImage.fromFile(tempFile);
      final faces = await _detector.processImage(inputImage);

      if (faces.isEmpty) {
        return FaceDetectionResult(
          faceDetected: false,
          imageWidth: decoded.width,
          imageHeight: decoded.height,
        );
      }

      // Pick the largest face
      final face = faces.reduce((a, b) =>
          (a.boundingBox.width * a.boundingBox.height) >=
                  (b.boundingBox.width * b.boundingBox.height)
              ? a
              : b);

      final bbox = face.boundingBox;

      // Crop face with margin
      final faceCrop = ImageUtils.cropFace(
        decoded,
        left: bbox.left.round(),
        top: bbox.top.round(),
        width: bbox.width.round(),
        height: bbox.height.round(),
        margin: AppConstants.faceCropMargin,
      );

      // Resize to model input size
      final resized =
          ImageUtils.resizeSquare(faceCrop, AppConstants.modelInputSize);

      return FaceDetectionResult(
        faceCrop: resized,
        boundingBox: FaceBoundingBox(
          left: bbox.left,
          top: bbox.top,
          width: bbox.width,
          height: bbox.height,
        ),
        faceDetected: true,
        imageWidth: decoded.width,
        imageHeight: decoded.height,
      );
    } catch (e) {
      // Fallback: use the full image if face detection fails
      final resized =
          ImageUtils.resizeSquare(decoded, AppConstants.modelInputSize);
      return FaceDetectionResult(
        faceCrop: resized,
        faceDetected: false,
        imageWidth: decoded.width,
        imageHeight: decoded.height,
      );
    }
  }

  /// Dispose the face detector.
  void dispose() {
    _faceDetector?.close();
    _faceDetector = null;
  }
}

// Note: Size is imported from dart:ui via Flutter's material package.
// If using this service in an isolate, pass the dimensions as doubles directly.
