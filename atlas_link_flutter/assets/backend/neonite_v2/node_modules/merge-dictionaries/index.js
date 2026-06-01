var _ = require('@sailshq/lodash');

// Create the customized merge function.
var merge = function(dictA, dictB) {
  return _.merge(dictA, dictB, function(a, b) {
    // If `a` is not a POJO, or it's an empty POJO, just replace it with `b`.
    // _.isPlainObject is fine here because we don't care about clobbering dictionaries that
    // came from custom constructors; our use case is merging config files together, so any
    // left-hand values should either be literals, POJOS or `undefined`.
    if (!_.isPlainObject(a) || _.keys(a).length === 0) { return b; }
    // For non-empty dictionaries (POJO or otherwise), use the default merge strategy.
  });
};

// Allow variadic usage.
// e.g. mergeDictionarys(dictOne, dictTwo, dictThree, dictFour, ...)
module.exports = function() {

  // Special case: if only one arg is provided, just return it.
  if (arguments.length === 1) {
    return arguments[0];
  }

  // Otherwise use `_.reduce` to merge arguments from left to right.
  var args = Array.prototype.slice.call(arguments);
  var firstArg = args.shift();
  return _.reduce(args, function(memo, arg) {
    return merge(memo, arg);
  }, firstArg);

};
