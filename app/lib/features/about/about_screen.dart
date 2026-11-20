import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About EmoLens')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            // Logo
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/images/app_icon.png',
                width: 96,
                height: 96,
                errorBuilder: (_, __, ___) => Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.secondary],
                    ),
                  ),
                  child: const Icon(Icons.remove_red_eye_rounded,
                      color: Colors.white, size: 50),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppConstants.appName,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text('v${AppConstants.appVersion}',
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text(
              'Model v${AppConstants.modelVersion}',
              style: const TextStyle(color: AppColors.primary, fontSize: 12),
            ),
            const SizedBox(height: 32),
            _InfoCard(
              icon: Icons.info_outline_rounded,
              title: 'About',
              content:
                  'EmoLens is a research-grade mobile application designed to assist '
                  'caregivers of individuals with Down syndrome by providing real-time '
                  'emotion recognition via a local ESP32-CAM. The model is specifically '
                  'trained on Down syndrome facial expressions for improved accuracy.',
            ),
            const SizedBox(height: 12),
            _InfoCard(
              icon: Icons.psychology_rounded,
              title: 'AI Model',
              content:
                  'MobileNetV2 + Squeeze-and-Excitation (SE) attention block, trained '
                  'with transfer learning on the Down Syndrome Emotion Dataset. '
                  'Input: 224×224 RGB, normalized to [-1, 1]. '
                  'Classes: Happy 😊, Neutral 😐, Sad 😢. '
                  'Quantized to TFLite float16 for on-device inference.',
            ),
            const SizedBox(height: 12),
            _InfoCard(
              icon: Icons.lock_rounded,
              title: 'Privacy',
              content: AppConstants.privacyStatement +
                  '\n\nThe subjects of this application are a vulnerable population. '
                  'Caregiver supervision and informed consent are required at all times. '
                  'No biometric data is transmitted, stored in the cloud, or shared '
                  'with third parties.',
            ),
            const SizedBox(height: 12),
            _InfoCard(
              icon: Icons.school_rounded,
              title: 'Capstone Project',
              content:
                  'Built as a capstone project exploring adaptive AI for assistive '
                  'technology. The adaptive personalization system allows caregivers to '
                  'correct predictions, which can be used to fine-tune the model for '
                  'the individual.',
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;
  const _InfoCard({required this.icon, required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            Text(content,
                style: const TextStyle(
                    color: AppColors.textSecondary, height: 1.6)),
          ],
        ),
      ),
    );
  }
}

