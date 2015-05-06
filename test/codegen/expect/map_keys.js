var map_keys = dart.defineLibrary(map_keys, {});
var core = dart.import(core);
var math = dart.import(math);
(function(exports, core, math) {
  'use strict';
  // Function main: () → dynamic
  function main() {
    core.print(dart.map({'1': 2, '3': 4, '5': 6}));
    core.print(dart.map([1, 2, 3, 4, 5, 6]));
    core.print(dart.map({'1': 2, [`${dart.notNull(new math.Random().nextInt(2)) + 2}`]: 4, '5': 6}));
    let x = '3';
    core.print(dart.map(['1', 2, x, 4, '5', 6]));
    core.print(dart.map(['1', 2, null, 4, '5', 6]));
  }
  // Exports:
  exports.main = main;
})(map_keys, core, math);
//# sourceMappingURL=map_keys.js.map