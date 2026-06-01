/**
 * Module dependencies
 */

var switchback = require('switchback');
var captains = require('captains-log');



/**
 * Reporter
 *
 * Hybrid between:
 * + switchback
 * + logger
 * + EventEmitter
 * + Stream
 *
 * Usage:
 * require('reporter')
 *
 */
module.exports = Reporter;

/**
 * Factory
 *
 * @param  {Object|Function} patch
 * @param  {Object} defaultHandlers
 * @return {Reporter} a new reporter
 */
function Reporter (patch, defaultHandlers) {
  patch = patch || {};
  defaultHandlers = defaultHandlers || {};
  if ( typeof patch !== 'function' && (typeof patch !== 'object' || patch === null) ) {
    throw new Error('Invalid usage: must provide a function or object.');
  }

  // Construct logger
  var logger = captains();


  // Set up implicit defaults for `defaultHandlers`
  if (defaultHandlers.success === undefined) {
    defaultHandlers.success = function(){};
  }
  if (defaultHandlers.error === undefined) {
    defaultHandlers.error = logger.error;
  }
  if (defaultHandlers.end === undefined) {
    defaultHandlers.end = function(){};
  }


  // Construct a switchback
  var reporter = switchback(patch, defaultHandlers);

  // Mixin streaming / logging functionality
  reporter.write = logger.info;
  reporter.log   = logger;

  /**
   * Mixin `extend()` method
   * @param  {Object|Function} patch
   * @return {Reporter} a new reporter
   */
  reporter.extend = Reporter;

  return reporter;
}


