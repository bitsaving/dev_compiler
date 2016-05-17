dart_library.library('js', null, /* Imports */[
  'dart_sdk'
], function(exports, dart_sdk) {
  'use strict';
  const core = dart_sdk.core;
  const js = dart_sdk.js;
  const dart = dart_sdk.dart;
  const dartx = dart_sdk.dartx;
  const js$ = Object.create(null);
  js$.JS = class JS extends core.Object {
    new(name) {
      if (name === void 0) name = null;
      this.name = name;
    }
  };
  dart.setSignature(js$.JS, {
    constructors: () => ({new: [js$.JS, [], [core.String]]})
  });
  js$._Anonymous = class _Anonymous extends core.Object {
    new() {
    }
  };
  dart.setSignature(js$._Anonymous, {
    constructors: () => ({new: [js$._Anonymous, []]})
  });
  js$.anonymous = dart.const(new js$._Anonymous());
  js$.allowInteropCaptureThis = js.allowInteropCaptureThis;
  js$.allowInterop = js.allowInterop;
  // Exports:
  exports.js = js$;
});
