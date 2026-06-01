var _ = require('@sailshq/lodash');

module.exports = function(dictA, dictB) {
  return _.merge(dictA, dictB, function(a, b) {
    // If `a` is not a POJO, or it's an empty POJO, just replace it with `b`.
    // _.isPlainObject is fine here because we don't care about clobbering dictionaries that
    // came from custom constructors; our use case is merging config files together, so any
    // left-hand values should either be literals, POJOS or `undefined`.
    if (!_.isPlainObject(a) || _.keys(a).length === 0) { return b; }
    // For non-empty dictionaries (POJO or otherwise), use the default merge strategy.
  });
};
