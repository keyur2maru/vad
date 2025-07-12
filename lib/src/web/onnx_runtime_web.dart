// onnx_runtime_web.dart
// Direct interop with onnxruntime-web using dart:js_interop

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'speech_probabilities.dart';

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
  external JSPromise<InferenceSession> create(JSAny modelUrl);
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
  Float32List? _h;
  Float32List? _c;

  SileroV5Model._(this._session) {
    resetState();
  }

  static Future<SileroV5Model> create(String modelUrl) async {
    // Set WASM paths for ONNX Runtime
    ort.env.wasm.wasmPaths = globalContext.getProperty('location'.toJS)!
        .getProperty('origin'.toJS)!.toString() + '/assets/packages/vad/assets/';
    
    final session = await ort.InferenceSession.create(modelUrl.toJS).toDart;
    return SileroV5Model._(session);
  }

  @override
  void resetState() {
    _h = Float32List(2 * 1 * 64); // 2 * batch_size * hidden_size
    _c = Float32List(2 * 1 * 64);
  }

  @override
  Future<SpeechProbabilities> process(Float32List frame) async {
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
      'input': inputTensor,
      'h0': hTensor,
      'c0': cTensor,
    }.jsify()!;

    final results = await _session.run(feeds).toDart;
    
    final output = results['output'];
    final newH = results['hn'];
    final newC = results['cn'];

    // Update state
    _h = newH.data;
    _c = newC.data;

    final prob = output.data[0];
    return SpeechProbabilities(
      isSpeech: prob,
      notSpeech: 1.0 - prob,
    );
  }
}

class SileroLegacyModel implements VadModel {
  final InferenceSession _session;
  Float32List? _h;
  Float32List? _c;

  SileroLegacyModel._(this._session) {
    resetState();
  }

  static Future<SileroLegacyModel> create(String modelUrl) async {
    // Set WASM paths for ONNX Runtime
    ort.env.wasm.wasmPaths = globalContext.getProperty('location'.toJS)!
        .getProperty('origin'.toJS)!.toString() + '/assets/packages/vad/assets/';
    
    final session = await ort.InferenceSession.create(modelUrl.toJS).toDart;
    return SileroLegacyModel._(session);
  }

  @override
  void resetState() {
    _h = Float32List(2 * 1 * 64); // 2 * batch_size * hidden_size
    _c = Float32List(2 * 1 * 64);
  }

  @override
  Future<SpeechProbabilities> process(Float32List frame) async {
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
      'input': inputTensor,
      'h': hTensor,
      'c': cTensor,
    }.jsify()!;

    final results = await _session.run(feeds).toDart;
    
    final output = results['output'];
    final newH = results['hn'];
    final newC = results['cn'];

    // Update state
    _h = newH.data;
    _c = newC.data;

    final prob = output.data[0];
    return SpeechProbabilities(
      isSpeech: prob,
      notSpeech: 1.0 - prob,
    );
  }
}