// resampler.dart
// Audio resampler - ported from resampler.ts

import 'dart:typed_data';
import 'dart:math' as math;

class ResamplerOptions {
  final int nativeSampleRate;
  final int targetSampleRate;
  final int targetFrameSize;

  const ResamplerOptions({
    required this.nativeSampleRate,
    required this.targetSampleRate,
    required this.targetFrameSize,
  });
}

class Resampler {
  final ResamplerOptions options;
  final List<double> _inputBuffer = [];
  double _lastFilteredValue = 0.0;
  static const double _filterCoefficient = 0.2; // Hardcoded for 8kHz to 16kHz case

  Resampler(this.options) {
    if (options.nativeSampleRate < 16000) {
      print('Warning: nativeSampleRate is too low. Should have 16000 = targetSampleRate <= nativeSampleRate, will be upsampled');
    }
  }

  List<Float32List> process(Float32List audioFrame) {
    final outputFrames = <Float32List>[];

    for (final sample in audioFrame) {
      _inputBuffer.add(sample);

      while (_hasEnoughDataForFrame()) {
        final outputFrame = _generateOutputFrame();
        outputFrames.add(outputFrame);
      }
    }

    return outputFrames;
  }

  bool _hasEnoughDataForFrame() {
    return (_inputBuffer.length * options.targetSampleRate) /
            options.nativeSampleRate >=
        options.targetFrameSize;
  }

  double _lowPassFilter(double sample) {
    _lastFilteredValue = _lastFilteredValue +
        _filterCoefficient * (sample - _lastFilteredValue);
    return _lastFilteredValue;
  }

  Float32List _generateOutputFrame() {
    final outputFrame = Float32List(options.targetFrameSize);
    final ratio = options.nativeSampleRate / options.targetSampleRate;

    if (ratio < 1) {
      // Upsampling case
      final inputToOutputRatio = options.targetSampleRate / options.nativeSampleRate;

      for (int outputIndex = 0; outputIndex < options.targetFrameSize; outputIndex++) {
        final inputPosition = outputIndex / inputToOutputRatio;
        final inputIndex = inputPosition.floor();
        final fraction = inputPosition - inputIndex;

        if (inputIndex + 1 < _inputBuffer.length) {
          final sample1 = _lowPassFilter(_inputBuffer[inputIndex]);
          final sample2 = _lowPassFilter(_inputBuffer[inputIndex + 1]);
          outputFrame[outputIndex] = sample1 + fraction * (sample2 - sample1);
        } else {
          outputFrame[outputIndex] = _lowPassFilter(_inputBuffer[inputIndex]);
        }
      }

      final samplesUsed = (options.targetFrameSize / inputToOutputRatio).ceil();
      _inputBuffer.removeRange(0, math.min(samplesUsed, _inputBuffer.length));
    } else {
      // Downsampling case
      int outputIndex = 0;
      int inputIndex = 0;

      while (outputIndex < options.targetFrameSize) {
        double sum = 0;
        int num = 0;
        final targetInputIndex = math.min(
          _inputBuffer.length,
          ((outputIndex + 1) * options.nativeSampleRate) ~/ options.targetSampleRate,
        );

        while (inputIndex < targetInputIndex) {
          sum += _inputBuffer[inputIndex];
          num++;
          inputIndex++;
        }

        outputFrame[outputIndex] = num > 0 ? sum / num : 0.0;
        outputIndex++;
      }

      _inputBuffer.removeRange(0, math.min(inputIndex, _inputBuffer.length));
    }

    return outputFrame;
  }
}