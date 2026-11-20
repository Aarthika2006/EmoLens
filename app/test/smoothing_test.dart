import 'package:test/test.dart';

/// Tests for EMA (Exponential Moving Average) smoothing logic.
/// This replicates the smoothing done in EmotionNotifier.
void main() {
  group('EMA Smoothing Logic', () {
    Map<String, double> _applyEma(
      Map<String, double> current,
      Map<String, double> newProbs,
      int window,
    ) {
      final alpha = 2.0 / (window + 1);
      final result = <String, double>{};
      for (final key in current.keys) {
        final prob = newProbs[key] ?? 0.0;
        result[key] = alpha * prob + (1 - alpha) * current[key]!;
      }
      return result;
    }

    String _winner(Map<String, double> probs) {
      return probs.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    }

    test('single input dominates for window=3', () {
      final ema = {'Happy': 0.0, 'Neutral': 0.0, 'Sad': 0.0};
      final input = {'Happy': 1.0, 'Neutral': 0.0, 'Sad': 0.0};
      final result = _applyEma(ema, input, 3);
      expect(_winner(result), equals('Happy'));
    });

    test('repeated inputs converge to true label', () {
      var ema = {'Happy': 0.33, 'Neutral': 0.33, 'Sad': 0.34};
      final trueInput = {'Happy': 0.0, 'Neutral': 0.0, 'Sad': 1.0};
      for (int i = 0; i < 20; i++) {
        ema = _applyEma(ema, trueInput, 5);
      }
      expect(_winner(ema), equals('Sad'));
      expect(ema['Sad']!, greaterThan(0.9));
    });

    test('label does not flip on single noise frame', () {
      var ema = {'Happy': 0.0, 'Neutral': 0.0, 'Sad': 0.0};
      // 10 frames of Happy
      for (int i = 0; i < 10; i++) {
        ema = _applyEma(ema, {'Happy': 1.0, 'Neutral': 0.0, 'Sad': 0.0}, 7);
      }
      expect(_winner(ema), equals('Happy'));

      // One noise Sad frame
      ema = _applyEma(ema, {'Happy': 0.0, 'Neutral': 0.0, 'Sad': 1.0}, 7);
      // Should still be Happy due to smoothing
      expect(_winner(ema), equals('Happy'));
    });

    test('alpha calculation for different windows', () {
      // window=3 → alpha=0.5
      expect(2.0 / (3 + 1), closeTo(0.5, 0.001));
      // window=5 → alpha=0.333
      expect(2.0 / (5 + 1), closeTo(0.333, 0.001));
      // window=9 → alpha=0.2
      expect(2.0 / (9 + 1), closeTo(0.2, 0.001));
    });

    test('all probabilities stay in [0, 1] range', () {
      var ema = {'Happy': 0.0, 'Neutral': 0.0, 'Sad': 0.0};
      final frames = [
        {'Happy': 0.9, 'Neutral': 0.05, 'Sad': 0.05},
        {'Happy': 0.1, 'Neutral': 0.8, 'Sad': 0.1},
        {'Happy': 0.05, 'Neutral': 0.05, 'Sad': 0.9},
      ];
      for (int i = 0; i < 15; i++) {
        final frame = frames[i % frames.length];
        ema = _applyEma(ema, frame, 5);
      }
      for (final v in ema.values) {
        expect(v, greaterThanOrEqualTo(0.0));
        expect(v, lessThanOrEqualTo(1.0));
      }
    });
  });
}

