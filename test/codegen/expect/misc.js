dart_library.library('misc', null, /* Imports */[
  'dart/_runtime',
  'dart/core'
], /* Lazy imports */[
], function(exports, dart, core) {
  'use strict';
  let dartx = dart.dartx;
  exports[dart.uri] = 'file:///usr/local/google/vsm/dev_compiler/test/codegen/misc.dart';
  class _Uninitialized extends core.Object {
    _Uninitialized() {
    }
  }
  dart.setSignature(_Uninitialized, {
    constructors: () => ({_Uninitialized: [_Uninitialized, []]})
  });
  _Uninitialized[dart.owner] = exports;
  const UNINITIALIZED = dart.const(new _Uninitialized());
  const Generic$ = dart.generic(function(T) {
    class Generic extends core.Object {
      get type() {
        return Generic$();
      }
      m() {
        return core.print(T);
      }
    }
    dart.setSignature(Generic, {
      methods: () => ({m: [dart.dynamic, []]})
    });
    Generic[dart.owner] = exports;
    return Generic;
  });
  let Generic = Generic$();
  class Base extends core.Object {
    Base() {
      this.x = 1;
      this.y = 2;
    }
    ['=='](obj) {
      return dart.is(obj, Base) && obj.x == this.x && obj.y == this.y;
    }
  }
  Base[dart.owner] = exports;
  class Derived extends core.Object {
    Derived() {
      this.z = 3;
    }
    ['=='](obj) {
      return dart.is(obj, Derived) && obj.z == this.z && super['=='](obj);
    }
  }
  Derived[dart.owner] = exports;
  function _isWhitespace(ch) {
    return ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t';
  }
  dart.fn(_isWhitespace, core.bool, [core.String]);
  const expr = 'foo';
  const _escapeMap = dart.const(dart.map({'\n': '\\n', '\r': '\\r', '\f': '\\f', '\b': '\\b', '\t': '\\t', '\v': '\\v', '': '\\x7F', [`\${${expr}}`]: ''}));
  function main() {
    core.print(dart.toString(1));
    core.print(dart.toString(1.0));
    core.print(dart.toString(1.1));
    let x = 42;
    core.print(dart.equals(x, dart.dynamic));
    core.print(dart.equals(x, Generic));
    core.print(new (Generic$(core.int))().type);
    core.print(dart.equals(new Derived(), new Derived()));
    new (Generic$(core.int))().m();
  }
  dart.fn(main);
  // Exports:
  exports.UNINITIALIZED = UNINITIALIZED;
  exports.Generic$ = Generic$;
  exports.Generic = Generic;
  exports.Base = Base;
  exports.Derived = Derived;
  exports.expr = expr;
  exports.main = main;
});
