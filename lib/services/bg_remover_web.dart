import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

// Calls window.aetherraRemoveBg registered by web/bg_remover.js.
// That script uses @imgly/background-removal (WASM, runs entirely in browser).
@JS('aetherraRemoveBg')
external JSPromise<JSString> _aetherraRemoveBgJs(JSString base64Input);

Future<Uint8List?> removeBg(Uint8List imageBytes) async {
  final b64   = base64Encode(imageBytes);
  final jsStr = await _aetherraRemoveBgJs(b64.toJS).toDart;
  return base64Decode(jsStr.toDart);
}
