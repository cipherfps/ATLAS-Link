/**
 * Module dependencies
 */

var util = require('util');
var _ = require('@sailshq/lodash');
var constants = require('./constants');



/**
 * factory
 *
 * @return {Switchback}
 *
 * An anonymous function is used as the base for switchbacks so that
 * they are both dereferenceable AND callable.  This allows functions
 * which accept switchback definitions to maintain compatibility with
 * standard node callback conventions (which are better for many situations).
 *
 * This also means that instantiated switchbacks may be passed interchangably
 * into functions expecting traditional node callbacks, and everything will
 * "just work".
 */

module.exports = function(callbackContext) {

  var _switch = function( /* err, arg1, arg2, ..., argN */ ) {
    var args = Array.prototype.slice.call(arguments);

    // Trigger error handler
    var err = args[0];
    if (err) {
      // If the error has a `.exit` property that corresponds with the name of an exit,
      // call that exit instead of `error`. This makes it possible for `sb(e)` to work
      // as a type of clean, conventional error negotiation, allowing usage like:
      // ```
      // function (inputs, exits) {
      //   try { doStuff(); }
      //   catch (e) { return exits(e); }
      //   return exits();
      // }
      // ```
      if (_.isObject(err) && _.isString(err.exit) && _.isFunction(_switch[err.exit])) {
        // Also, if we're able to do this (i.e. a callback was supplied for this "exit")
        // then check to see if there was also an `.output` property provided.
        // If so, use it as the first argument when triggering the callback.
        if (!_.isUndefined(err.output)) {
          return _switch[err.exit].apply(callbackContext || this, [err.output]);
        }
        // Otherwise, just use the err object as-is.
        // (TODO: in `machine`, consider using the description, other metadata, etc.)
        else {
          return _switch[err.exit].apply(callbackContext || this, args);
        }
      }
      return _switch.error.apply(callbackContext || this, args);
    }
    return _switch.success.apply(callbackContext || this, args.slice(1));
  };

  // Mark switchback function so it can be identified for tests
  _switch[constants.telltale.key] = constants.telltale.value;

  // Mix in non-enumerable `.inspect()` method
  Object.defineProperty(_switch, 'inspect', { enumerable: false, writable: true });
  _switch.inspect = function () { return '[Switchback]'; };

  return _switch;
};
