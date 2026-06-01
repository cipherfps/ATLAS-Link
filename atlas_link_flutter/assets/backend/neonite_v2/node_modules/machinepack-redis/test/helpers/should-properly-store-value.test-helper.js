/**
 * Module dependencies
 */

var util = require('util');
var _ = require('@sailshq/lodash');
var Pack = require('../../');

/**
 * shouldProperlyStoreValue()
 *
 * Test helper for use within an `it()` block.
 *
 * @param  {Dictionary} opts
 *         @required  {===}    connection
 *         @required  {*}      valueToStore
 *         @required  {String} key
 *
 * @param  {Function} done
 */

module.exports = function shouldProperlyStoreValue (opts, done){
  Pack.cacheValue({
    connection: opts.connection,
    key: opts.key,
    value: opts.valueToStore,
    ttl: opts.ttl
  }).switch({
    error: done,
    success: function (report){
      Pack.getCachedValue({
        connection: opts.connection,
        key: opts.key
      }).switch({
        error: done,
        success: function (report){
          if (!_.isEqual(report.value, opts.valueToStore)) {
            return done(new Error('Incorrect value seems to have been stored (specifically, the value retrieved does not match value that was stored).  Expected:\n' + util.inspect(opts.valueToStore, {depth: null}) + '\nBut got:\n' + util.inspect(report.value, {depth: null})));
          }
          return done();
        }
      });
    }
  });
};
