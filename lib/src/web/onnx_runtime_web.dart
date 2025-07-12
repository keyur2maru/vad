// onnx_runtime_web.dart
// Direct interop with onnxruntime-web using dart:js_interop

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'speech_probabilities.dart';
import 'model_utils.dart';

// ONNX Runtime Web interop bindings
@JS('ort')
external OrtGlobal get ort;

@JS()
extension type OrtGlobal._(JSObject _) implements JSObject {
  external EnvNamespace get env;
  external InferenceSessionConstructor get InferenceSession;
  external TensorConstructor get Tensor;
}

@JS()
extension type EnvNamespace._(JSObject _) implements JSObject {
  external WasmNamespace get wasm;
}

@JS()
extension type WasmNamespace._(JSObject _) implements JSObject {
  external set wasmPaths(String paths);
}

@JS()
extension type InferenceSessionConstructor._(JSObject _) implements JSObject {
  external JSPromise<InferenceSession> create(String modelUrl);
}

@JS()
extension type TensorConstructor._(JSObject _) implements JSObject {
  external Tensor createFromFloat32Array(String type, Float32List data, JSArray<JSNumber> dims);
}

@JS()
extension type InferenceSession._(JSObject _) implements JSObject {
  external JSPromise<RunResult> run(JSObject feeds);
}

@JS()
extension type Tensor._(JSObject _) implements JSObject {
  external Float32List get data;
  external JSArray<JSNumber> get dims;
}

@JS()
extension type RunResult._(JSObject _) implements JSObject {
  external Tensor operator [](String key);
}

// Silero VAD Model implementations
abstract class VadModel {
  Future<SpeechProbabilities> process(Float32List frame);
  void resetState();
}

class SileroV5Model implements VadModel {
  final InferenceSession _session;
  final Map<String, String> _inputNames;
  final Map<String, String> _outputNames;
  Float32List? _h;
  Float32List? _c;

  SileroV5Model._(this._session, this._inputNames, this._outputNames) {
    resetState();
  }

  static Future<SileroV5Model> create(String modelUrl) async {
    try {
      // Set WASM paths for ONNX Runtime
      final origin = globalContext.getProperty('location'.toJS)!
          .getProperty('origin'.toJS)!.toString();
      ort.env.wasm.wasmPaths = '$origin/assets/packages/vad/assets/';
      
      final session = await ort.InferenceSession.create(modelUrl).toDart;
      final inputNames = getModelInputNames('v5');
      final outputNames = getModelOutputNames('v5');
      
      return SileroV5Model._(session, inputNames, outputNames);
    } catch (e) {
      print('Error creating SileroV5Model: $e');
      rethrow;
    }
  }

  @override
  void resetState() {
    _h = Float32List(2 * 1 * 64); // 2 * batch_size * hidden_size
    _c = Float32List(2 * 1 * 64);
    // Fill with zeros
    for (int i = 0; i < _h!.length; i++) {
      _h![i] = 0.0;
    }
    for (int i = 0; i < _c!.length; i++) {
      _c![i] = 0.0;
    }
  }

  @override
  Future<SpeechProbabilities> process(Float32List frame) async {
    try {
      final inputTensor = ort.Tensor.createFromFloat32Array(
        'float32',
        frame,
        [1, frame.length].map((e) => e.toJS).toList().toJS,
      );

      final hTensor = ort.Tensor.createFromFloat32Array(
        'float32',
        _h!,
        [2, 1, 64].map((e) => e.toJS).toList().toJS,
      );

      final cTensor = ort.Tensor.createFromFloat32Array(
        'float32',
        _c!,
        [2, 1, 64].map((e) => e.toJS).toList().toJS,
      );

      final feeds = {
        _inputNames['input']!: inputTensor,
        _inputNames['state_h']!: hTensor,
        _inputNames['state_c']!: cTensor,
      }.jsify()!;

      final results = await _session.run(feeds).toDart;
      
      final output = results[_outputNames['output']!];
      final newH = results[_outputNames['state_h']!];
      final newC = results[_outputNames['state_c']!];

      // Update state
      _h = newH.data;
      _c = newC.data;

      final prob = output.data[0];
      return SpeechProbabilities(
        isSpeech: prob,
        notSpeech: 1.0 - prob,
      );
    } catch (e) {
      print('Error in SileroV5Model.process: $e');
      rethrow;
    }
  }
}

class SileroLegacyModel implements VadModel {
  final InferenceSession _session;
  final Map<String, String> _inputNames;
  final Map<String, String> _outputNames;
  Float32List? _h;
  Float32List? _c;

  SileroLegacyModel._(this._session, this._inputNames, this._outputNames) {
    resetState();
  }

  static Future<SileroLegacyModel> create(String modelUrl) async {
    try {
      // Set WASM paths for ONNX Runtime
      final origin = globalContext.getProperty('location'.toJS)!
          .getProperty('origin'.toJS)!.toString();
      ort.env.wasm.wasmPaths = '$origin/assets/packages/vad/assets/';
      
      final session = await ort.InferenceSession.create(modelUrl).toDart;
      final inputNames = getModelInputNames('legacy');
      final outputNames = getModelOutputNames('legacy');
      
      return SileroLegacyModel._(session, inputNames, outputNames);
    } catch (e) {
      print('Error creating SileroLegacyModel: $e');
      rethrow;
    }
  }

  @override
  void resetState() {
    _h = Float32List(2 * 1 * 64); // 2 * batch_size * hidden_size
    _c = Float32List(2 * 1 * 64);
    // Fill with zeros
    for (int i = 0; i < _h!.length; i++) {
      _h![i] = 0.0;
    }
    for (int i = 0; i < _c!.length; i++) {
      _c![i] = 0.0;
    }
  }

  @override
  Future<SpeechProbabilities> process(Float32List frame) async {
    try {
      final inputTensor = ort.Tensor.createFromFloat32Array(
        'float32',
        frame,
        [1, frame.length].map((e) => e.toJS).toList().toJS,
      );

      final hTensor = ort.Tensor.createFromFloat32Array(
        'float32',
        _h!,
        [2, 1, 64].map((e) => e.toJS).toList().toJS,
      );

      final cTensor = ort.Tensor.createFromFloat32Array(
        'float32',
        _c!,
        [2, 1, 64].map((e) => e.toJS).toList().toJS,
      );

      final feeds = {
        _inputNames['input']!: inputTensor,
        _inputNames['state_h']!: hTensor,
        _inputNames['state_c']!: cTensor,
      }.jsify()!;

      final results = await _session.run(feeds).toDart;
      
      final output = results[_outputNames['output']!];
      final newH = results[_outputNames['state_h']!];
      final newC = results[_outputNames['state_c']!];

      // Update state
      _h = newH.data;
      _c = newC.data;

      final prob = output.data[0];
      return SpeechProbabilities(
        isSpeech: prob,
        notSpeech: 1.0 - prob,
      );
    } catch (e) {
      print('Error in SileroLegacyModel.process: $e');
      rethrow;
    }
  }
}