// lib/src/platform/native/onnxruntime/graph_optimization.dart
// ignore_for_file: public_member_api_docs

// Dart imports:
import 'dart:ffi' as ffi;

// Project imports:
import 'package:vad/src/platform/native/onnxruntime/ort_session.dart';

/// Graph optimization level to use for VAD inference sessions.
///
/// Returns [GraphOptimizationLevel.ortEnableAll] everywhere except 32-bit
/// platforms, where it returns [GraphOptimizationLevel.ortDisableAll] to avoid a
/// native crash inside ONNX Runtime.
///
/// ONNX Runtime's `CommonSubexpressionElimination` pass hashes single-element
/// tensor attributes by casting the raw protobuf bytes directly to a typed
/// pointer and dereferencing it:
///
/// ```cpp
/// // onnxruntime/core/optimizer/common_subexpression_elimination.cc
/// // GetTensorAttributeHash()
/// UpdateHash(*reinterpret_cast<const float*>(attr_t.raw_data().data()), hash);
/// UpdateHash(*reinterpret_cast<const int64_t*>(attr_t.raw_data().data()), hash);
/// ```
///
/// A protobuf `raw_data` payload starts at an arbitrary byte offset, so those
/// pointers are usually misaligned. 64-bit targets tolerate the loads; 32-bit
/// ARM does not — the VFP float load and the 64-bit `ldrd` both require natural
/// alignment — so the process dies with `SIGBUS` / `BUS_ADRALN` inside
/// `CreateSessionFromArray`. Being a native signal, it cannot be caught from
/// Dart or Java.
///
/// Both bundled models trigger this, so it cannot be avoided by model choice:
/// `silero_vad_v5.onnx` holds 263 misaligned single-element INT64 attributes and
/// `silero_vad_legacy.onnx` holds 3 misaligned FLOAT ones. Graph transformers
/// only run at `Level1` and above, so disabling optimization skips the faulting
/// pass entirely.
///
/// See https://github.com/microsoft/onnxruntime/issues/26323 and
/// https://github.com/keyur2maru/vad/issues/21.
GraphOptimizationLevel defaultGraphOptimizationLevel() =>
    ffi.sizeOf<ffi.Pointer<ffi.Void>>() == 4
        ? GraphOptimizationLevel.ortDisableAll
        : GraphOptimizationLevel.ortEnableAll;
