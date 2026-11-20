import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import '../../core/theme/app_colors.dart';

class FeedbackScreen extends ConsumerStatefulWidget {
  final Uint8List? snapshotBytes;
  final String predictedLabel;
  final double confidence;

  const FeedbackScreen({
    super.key,
    this.snapshotBytes,
    required this.predictedLabel,
    required this.confidence,
  });

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  String? _selectedLabel;
  bool _saved = false;

  static const _labels = ['Happy', 'Neutral', 'Sad'];
  static const _emojis = {'Happy': '😊', 'Neutral': '😐', 'Sad': '😢'};

  Future<void> _saveCorrection(String label) async {
    setState(() => _selectedLabel = label);
    if (widget.snapshotBytes == null) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final corrDir = Directory('${dir.path}/corrections/$label');
      await corrDir.create(recursive: true);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${corrDir.path}/$ts.jpg');
      await file.writeAsBytes(widget.snapshotBytes!);
      setState(() => _saved = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved as $label — thank you for the feedback!'),
            backgroundColor: AppColors.happy,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _exportCorrections() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final corrDir = Directory('${dir.path}/corrections');
      final exists = await corrDir.exists();
      if (!mounted) return;
      if (!exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No corrections to export yet.')),
        );
        return;
      }
      final archive = Archive();
      int count = 0;
      await for (final entity in corrDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.jpg')) {
          count++;
          final bytes = await entity.readAsBytes();
          final relativeName = entity.path.substring(corrDir.path.length + 1);
          archive.addFile(ArchiveFile(relativeName, bytes.length, bytes));
        }
      }
      if (count == 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No correction images found to export.')),
        );
        return;
      }
      final zipEncoder = ZipEncoder();
      final zipBytes = zipEncoder.encode(archive);
      if (zipBytes != null) {
        Directory exportDir = Directory('/storage/emulated/0/Download');
        if (!await exportDir.exists()) {
          final ext = await getExternalStorageDirectory();
          exportDir = ext ?? dir;
        }
        final exportFile = File('${exportDir.path}/EmoLens_Corrections.zip');
        await exportFile.writeAsBytes(zipBytes);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count correction(s) exported to:\n${exportFile.path}'),
            backgroundColor: AppColors.happy,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Correct Label')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Snapshot
            if (widget.snapshotBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  widget.snapshotBytes!,
                  width: double.infinity,
                  height: 220,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 20),
            // Predicted
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(_emojis[widget.predictedLabel] ?? '❓',
                        style: const TextStyle(fontSize: 32)),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Model predicted:',
                            style: TextStyle(color: AppColors.textSecondary)),
                        Text(
                          widget.predictedLabel,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${(widget.confidence * 100).toStringAsFixed(1)}% confidence',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Was this correct? Tap the right emotion:',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
            ),
            const SizedBox(height: 16),
            // Label selection
            Row(
              children: _labels.map((label) {
                final isSelected = _selectedLabel == label;
                final isPredicted = label == widget.predictedLabel;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: _saved ? null : () => _saveCorrection(label),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: isSelected
                              ? AppColors.primary.withOpacity(0.2)
                              : AppColors.cardBackground,
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : isPredicted
                                    ? AppColors.textSecondary
                                    : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(_emojis[label]!,
                                style: const TextStyle(fontSize: 32)),
                            const SizedBox(height: 8),
                            Text(label,
                                style: TextStyle(
                                  color: isSelected ? AppColors.primary : Colors.white,
                                  fontWeight: FontWeight.w600,
                                )),
                            if (isPredicted)
                              const Text('(predicted)',
                                  style: TextStyle(
                                      color: AppColors.textSecondary, fontSize: 10)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: _exportCorrections,
              icon: const Icon(Icons.upload_rounded),
              label: const Text('Export Corrections for Retraining'),
            ),
            const SizedBox(height: 12),
            Text(
              'Corrections are stored locally and used to personalize the model. '
              'Export them to retrain with adaptive_personalization.py.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

