/**
 * Module dependencies
 */

var util = require('util');
var _ = require('@sailshq/lodash');
var factory = require('./factory');
var normalize = require('./normalize');
var constants = require('./constants');
var EventEmitter = require('events').EventEmitter;


/**
 * `switchback`
 *
 * Switching utility which builds and returns a handler which is capable
 * calling one of several callbacks.
 *
 * @param {Object|Function} callback
 *			- a switchback definition obj or a standard 1|2-ary node callback function.
 *
 * @param {Object} [defaultHandlers]
 *			- '*': supply a special callback for when none of the other handlers match
 *			- a string can be supplied, e.g. {'invalid': 'error'}, to "forward" one handler to another
 *			- otherwise a function should be supplied, e.g. { 'error': res.serverError }
 *
 * @param {Object} [callbackContext]
 *			- optional `this` context for callbacks
 *
 * @param {Boolean} immediate
 *      - optional  don't wait for setTimeout(0) before triggering callback.
 *                  this breaks event-emitter-style usage.
 *                  defaults to false
 */

var switchback = function(callback, defaultHandlers, callbackContext, immediate) {


  /**
   * @api private
   * @param  {Function} cb [description]
   */
  function _maybeWaitForNextTick(cb){
    if (immediate) { return cb(); }
    setTimeout(cb, 0);
  }

  // Track whether a single tick of the event loop has elapsed yet since
  // this switchback was instantiated.
  var atLeastOneTickHasElapsed;
  _maybeWaitForNextTick(function (){
    atLeastOneTickHasElapsed = true;
  });

  // Build switchback
  var Switchback = factory(callbackContext);

  // If callback is not a function or an object, I don't know wtf it is,
  // so let's just return early before anything bad happens, hmm?
  if (!_.isObject(callback) && !_.isFunction(callback)) {
    // Actually let's not.
    // Instead, make the new switchback an EventEmitter
    var e = new EventEmitter();
    Switchback.emit = function() {
      var args = Array.prototype.slice.call(arguments);

      // This will invoke the final runtime function
      //
      // But first ensure at least a single cycle of the event loop has elapsed
      // since this switchback was instantiated
      if (atLeastOneTickHasElapsed) {
        return e.emit.apply(e, args);
      }
      else {
        _maybeWaitForNextTick(function (){
          return e.emit.apply(e, args);
        });
      }
    };
    Switchback.on = function(evName, handler) {
      if (immediate) {
        throw (function (){
          var _err = new Error('Switchback can not be used as an EventEmitter (i.e. `.on()`) when 4th argument (`immediate`) is set to true.');
          _err.code = 'SWITCHBACK:E_USAGE';
          return _err;
        })();
      }
      return e.on.apply(e, Array.prototype.slice.call(arguments));
    };

    // Then emit the appropriate event when the switchback is triggered.
    callback = {
      error: function(err) {
        Switchback.emit('error', err);
      },
      success: function( /*...*/ ) {
        Switchback.emit.apply(e, ['success'].concat(Array.prototype.slice.call(arguments)));
      }
    };
  }



  // Normalize `callback` to a switchback definition object.
  callback = normalize.callback(callback, callbackContext);

  // Attach specified handlers
  _.extend(Switchback, callback);


  // This is here as a failsafe to solve issues when no error callback is specified.
  var MAX_WILDCARD_FWDS = 15;
  var numWildcardFwds = 0;

  // Supply a handful of default handlers to provide better error messages.
  var getWildcardCaseHandler = function(caseName, switchbackErrorMsg) {
    return function unknownCase( /* ... */ ) {
      var args = Array.prototype.slice.call(arguments);

      // Build an error message that combines the error msg from switchback
      // with the actual error being passed in to the callback.
      var combinedError = '';

      // Build up a pretty-printed version of the actual error from the callback
      // (maintain the stack trace if at all possible)
      var actualErr = args[0];
      if (!_.isUndefined(actualErr)) {
        var prettifiedActualErr;
        if (_.isObject(actualErr) && actualErr instanceof Error){
          prettifiedActualErr = actualErr.stack;
        }
        else {
          prettifiedActualErr = util.inspect(args[0], false, null);
        }
        combinedError += prettifiedActualErr;
      }

      // Add on the error msg from switchback
      if (!_.isUndefined(switchbackErrorMsg)) {
        combinedError += '        ' + switchbackErrorMsg;
      }

      // Before attempting to call error handler, ensure that we're not
      // in an infinite loop.
      if (numWildcardFwds > MAX_WILDCARD_FWDS) {
        throw new Error('Switchback: handlers object (' + util.inspect(defaultHandlers) + ') has a cyclic redirect.');
      }

      // If a callback fn exists under the '*' or 'error' key in default handlers, call it
      if (_.isObject(defaultHandlers)){
        if (_.isFunction(defaultHandlers['*'])) {
          return defaultHandlers['*'](combinedError);
        }
        if (_.isFunction(defaultHandlers.error)) {
          return defaultHandlers.error(combinedError);
        }
      }
      // If a callback fn exists under the '*' or 'error' key in Switchback, call it
      if (_.isObject(Switchback)){
        if (_.isFunction(Switchback['*'])) {
          return Switchback['*'](combinedError);
        }
        if (_.isFunction(Switchback.error)) {
          return Switchback.error(combinedError);
        }
      }
      // console.log('defaultHandlers', defaultHandlers);
      // console.log('Switchback', Switchback);
      // console.log('Switchback["*"]', Switchback['*']);
      // console.log('Switchback["error"]', Switchback['error']);

      // Otherwise just throw out of frustration
      throw new Error(combinedError);
    };
  };

  // redirect any handler defaults specified as strings
  if (_.isObject(defaultHandlers)) {
    defaultHandlers = _.mapValues(defaultHandlers, function(handler, name) {
      if (_.isFunction(handler)) { return handler; }

      // Closure which will resolve redirected handler
      return function() {
        var runtimeHandler = handler;
        var runtimeArgs = Array.prototype.slice.call(arguments);
        var runtimeCtx = callbackContext || this;

        // Track previous handler to make usage error messages more useful.
        var prevHandler;

        // No more than 5 "redirects" allowed (prevents never-ending loop)
        var MAX_FORWARDS = 5;
        var numIterations = 0;
        do {
          prevHandler = runtimeHandler;
          runtimeHandler = Switchback[runtimeHandler];
          // console.log('redirecting '+name+' to "'+prevHandler +'"-- got ' + runtimeHandler);
          numIterations++;
        }
        while (_.isString(runtimeHandler) && numIterations <= MAX_FORWARDS);

        if (numIterations > MAX_FORWARDS) {
          throw new Error('Switchback: Default handlers object (' + util.inspect(defaultHandlers) + ') has a cyclic redirect.');
        }

        // Redirects to unknown handler
        if (!_.isFunction(runtimeHandler)) {
          runtimeHandler = getWildcardCaseHandler(runtimeHandler, '`' + name + '` case triggered, but no handler was implemented.');
        }

        // Invoke final runtime function
        //
        // But first ensure at least a single cycle of the event loop has elapsed
        // since this switchback was instantiated
        if (atLeastOneTickHasElapsed) {
          runtimeHandler.apply(runtimeCtx, runtimeArgs);
        }
        // Otherwise wait until that happens and then invoke the runtime function
        else {
          _maybeWaitForNextTick(function (){
            runtimeHandler.apply(runtimeCtx, runtimeArgs);
          });
        }

      };
    });
  }

  _.defaults(Switchback, defaultHandlers, {
    success: getWildcardCaseHandler('success', '`success` case triggered, but no handler was implemented.'),
    error: getWildcardCaseHandler('error', '`error` case triggered, but no handler was implemented.'),
    invalid: getWildcardCaseHandler('invalid', '`invalid` case triggered, but no handler was implemented.')
  });

  return Switchback;
};


/**
 * `isSwitchback`
 *
 * @param  {*}  something
 * @return {Boolean}           [whether `something` is a valid switchback instance]
 */
switchback.isSwitchback = function(something) {
  return _.isObject(something) && something[constants.telltale.key] === constants.telltale.value;
};




module.exports = switchback;


