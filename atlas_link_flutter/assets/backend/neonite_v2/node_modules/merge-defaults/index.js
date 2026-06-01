var _ = require('@sailshq/lodash');

/**
 * defaultsDeep
 *
 * Implement a deep version of `_.defaults`.
 *
 * This method is hopefully temporary, until lodash has something
 * similar that can be called in a single method.  For now, it's
 * worth it to use a temporary module for readability.
 * (i.e. I know what `_.defaults` means offhand- not true for `_.partialRight`)
 */

// In case the end user decided to do `_.defaults = require('merge-defaults')`,
// before doing anything else, let's make SURE we have a reference to the original
// `_.defaults()` method definition.
var origLodashDefaults = _.defaults;

// Corrected: see https://github.com/lodash/lodash/issues/540
// module.exports = function (/* ... */) {
  
//   if (typeof arguments[0] !== 'object') return origLodashDefaults.apply(_, Array.prototype.slice.call(arguments));
//   else {
//     var result = _mergeDefaults.apply(_, Array.prototype.slice.call(arguments));

//     // Ensure that original object is mutated
//     _.merge(arguments[0], result);

//     return result;
//   }
// };

module.exports = _.partialRight(_.merge, function recursiveDefaults ( /* ... */ ) {

  // Ensure dates and arrays are not recursively merged
  if (_.isArray(arguments[0]) || _.isDate(arguments[0])) {
    return arguments[0];
  }
  return _.merge(arguments[0], arguments[1], recursiveDefaults);
});

//origLodashDefaults.apply(_, Array.prototype.slice.call(arguments));

// module.exports = _.partialRight(_.merge, _.defaults);

// module.exports = _.partialRight(_.merge, function deep(a, b) {
//   // Ensure dates and arrays are not recursively merged
//   if (_.isArray(a) || _.isDate(a)) {
//     return a;
//   }
//   else return _.merge(a, b, deep);
// });