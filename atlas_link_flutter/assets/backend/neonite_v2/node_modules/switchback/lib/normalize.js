/**
 * Module dependencies
 */

var util = require('util');
var _ = require('@sailshq/lodash');



module.exports = {


  /**
   * `normalize.callback( callback )`
   *
   * If `callback` is provided as a function, transform it into
   * a "Switchback Definition Object" by using modified copies
   * of the original callback function as error/success handlers.
   *
   * @param  {Function|Object} callback [cb function or switchback def]
   * @return {Object}                   [switchback def]
   */
  callback: function _normalizeCallback(callback, callbackContext) {

    if (_.isFunction(callback)) {
      var _originalCallbackFn = callback;
      callback = {
        success: function() {
          // Shift arguments over (prepend a `null` first argument)
          // so this will never be perceived as an `err` when it's
          // used as a traditional callback
          var args = Array.prototype.slice.call(arguments);
          args.unshift(null);
          _originalCallbackFn.apply(callbackContext || this, args);
        },
        error: function() {
          // Ensure a first arg exists (err)
          // (if not, prepend an anonymous Error)
          var args = Array.prototype.slice.call(arguments);
          if (!args[0]) {
            args[0] = new Error('An error occurred. The error exit was triggered on a switchback that is being handled with a callback function in userland. And since no truthy argument was provided, switchback created this anonymous error.');
          }
          _originalCallbackFn.apply(callbackContext || this, args);
        }
      };
      callback = callback || {};
    }
    return callback;
  }
};
