import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/models/session.dart';
import '../../core/theme/app_colors.dart';

final historyRepoProvider = Provider<HistoryRepository>((ref) {
  final repo = HistoryRepository();
  ref.onDispose(repo.close);
  return repo;
});

final sessionsProvider = FutureProvider<List<Session>>((ref) {
  return ref.read(historyRepoProvider).getAllSessions();
});

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            onPressed: sessionsAsync.valueOrNull?.isNotEmpty ?? false
                ? () => _exportCsv(context, ref, sessionsAsync.value!)
                : null,
            tooltip: 'Export CSV',
          ),
        ],
      ),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (sessions) {
          if (sessions.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded,
                      size: 80, color: AppColors.textSecondary),
                  SizedBox(height: 16),
                  Text('No sessions yet',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 18)),
                  SizedBox(height: 8),
                  Text('Start a session from the Dashboard',
                      style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sessions.length,
            itemBuilder: (context, i) => _SessionCard(session: sessions[i]),
          );
        },
      ),
    );
  }

  Future<void> _exportCsv(
      BuildContext context, WidgetRef ref, List<Session> sessions) async {
    final rows = [
      [
        'ID',
        'Start Time',
        'End Time',
        'Duration',
        'Happy%',
        'Neutral%',
        'Sad%',
        'Total Frames'
      ],
      ...sessions.map((s) => [
            s.id,
            s.startTime.toIso8601String(),
            s.endTime?.toIso8601String() ?? '',
            s.durationFormatted,
            s.happyPercent.toStringAsFixed(1),
            s.neutralPercent.toStringAsFixed(1),
            s.sadPercent.toStringAsFixed(1),
            s.totalFrames,
          ]),
    ];
    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/emolens_history.csv');
    await file.writeAsString(csv);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('History exported to ${file.path}'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }
}

class _SessionCard extends StatelessWidget {
  final Session session;
  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, y – HH:mm');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.access_time_rounded,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(fmt.format(session.startTime),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
                const Spacer(),
                Text(session.durationFormatted,
                    style: const TextStyle(
                        color: AppColors.primary, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            // Emotion bar
            if (session.totalFrames > 0) ...[
              Row(
                children: [
                  _EmotionBar('😊 ${session.happyPercent.toStringAsFixed(0)}%',
                      session.happyPercent / 100, AppColors.happy),
                  const SizedBox(width: 4),
                  _EmotionBar(
                      '😐 ${session.neutralPercent.toStringAsFixed(0)}%',
                      session.neutralPercent / 100,
                      AppColors.neutral),
                  const SizedBox(width: 4),
                  _EmotionBar('😢 ${session.sadPercent.toStringAsFixed(0)}%',
                      session.sadPercent / 100, AppColors.sad),
                ],
              ),
            ] else
              const Text('No frames recorded',
                  style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text('${session.totalFrames} frames analyzed',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _EmotionBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _EmotionBar(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: (value * 100).round().clamp(1, 100),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: color.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
