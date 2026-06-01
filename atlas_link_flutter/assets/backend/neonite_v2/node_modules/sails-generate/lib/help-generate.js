/**
 * Module dependencies
 */

var util = require('util');
var path = require('path');
var _ = require('@sailshq/lodash');
var async = require('async');
var reportback = require('reportback')();
var pathToRegexp = require('./path-to-regexp');
var generateTarget = require('./generate-target');



/**
 * Run a generator given an existing scope.
 *
 * @param  {Dictionary|String} Generator
 * @param  {Dictionary} scope
 * @param  {Switchback} cb
 */

module.exports = function helpGenerate(Generator, scope, cb) {
  scope = scope || {};

  // Ensure that, if provided, `rootPath` is a string.
  if (!_.isUndefined(scope.rootPath)) {
    if (!_.isString(scope.rootPath)) {
      return cb(new Error('Consistency violation: If provided, `scope.rootPath` must be a string.  Instead, sails-generate got: ' + util.inspect(scope.rootPath)));
    }
    // FUTURE: Ensure that `rootPath` is reasonable (i.e. within some configurable, highest-acceptable
    // path) to prevent accidental smashing of your filesystem if installing a weird generator, etc.
  }

  // Ensure that, if provided, `args` is an array.
  if (!_.isUndefined(scope.args)) {
    if (!_.isArray(scope.args)) {
      return cb(new Error('Consistency violation: If provided, `scope.args` must be an array.  Instead, sails-generate got: ' + util.inspect(scope.args)));
    }
  }


  // Provide some implicit defaults for the incoming scope.
  _.defaults(scope, {


    // Starting point
    // (should be overidden as needed in generators' `before()` method)
    rootPath: process.cwd(),

    // command-line arguments
    // (avoid changing)
    //
    // For example, if this is `sails-generate-foo`:
    // `sails generate foo bar`
    // -> args = ['bar']
    //
    args: [],


    // Private options:

    // Maximum recursive depth
    _maxHops: 100,

    // current recursion depth w/i a generator's target set
    // (useful for preventing infinite loops)
    _depth: 0

  });


  // Resolve string shorthand for generator defs
  // e.g.
  //  Convert:
  //    `'sails-generate-whatever'`
  //  Into:
  //    `{ generator: 'sails-generate-whatever' }`
  //
  // > Note that, in this case, the passed-in `Generator`
  // > is actually the _NAME_ of a generator, not a generator
  // > definition.
  if (typeof Generator === 'string') {
    var generatorName = Generator;
    Generator = {
      generator: generatorName
    };
  }//>-

  // If our generator definition (`Generator`) doesn't contain `before` or `targets`,
  // then use a noop asynchronous function for `before`, and/or an empty
  // dictionary for `targets`.
  _.defaults(Generator, {
    before: function(scope, proceed) { return proceed(); },
    targets: {}
  });


  // Build switchback.
  var sb = reportback.extend(cb, {
    error: cb.error,
    invalid: cb.invalid,
    alreadyExists: 'error'
  });


  // Sanity check: Ensure a rootPath exists.
  if (!scope.rootPath) {
    return sb(new Error('Consistency violation: Missing scope variable: `rootPath`\nPlease make sure it is specified and try again.  If you are seeing this message, one or more custom generators installed on this computer may have an internal error.  If there are no custom generators installed in Sails, this could be indicative of a bug or version compatibility / `npm link` issue with the globally-installed Sails generators.  If you need ruther help, visit https://sailsjs.com/support.'));
  }


  // Run the `before()` method defined in the generator defintion.
  Generator.before(scope, reportback.extend({
    error: function(err) {
      if (err.code === 'E_CANCELED') {
        // Special handling of the "E_CANCELED" error.
        // (just ignore it and pretend everything worked)
        return sb();
      } else {
        // Normal error handling
        return sb(err);
      }
    },
    invalid: sb.invalid,
    success: function() {

      // Emit output
      sb.log.verbose('Generating ' + util.inspect(Generator) + ' at ' + scope.rootPath + '...');

      // Process all of the generator's targets concurrently.
      async.each(Object.keys(Generator.targets), function (keyPath, proceed) {
        proceed = reportback.extend(proceed);

        // Create a new scope object for this target,
        // with references to the important bits of the original.
        // (depth will be passed-by-value, but that's what we want)
        //
        // Then generate the target, passing along a reference to
        // the base `generate` method to allow for recursive generators.
        var target = Generator.targets[keyPath];
        if (!target) { return proceed(new Error('Generator error: Invalid target: {"' + keyPath + '": ' + util.inspect(target) + '}')); }

        // Input tolerance
        if (keyPath === '') {
          keyPath = '.';
        }

        // Interpret `keyPath` using express's parameterized route conventions,
        // first parsing params, then replacing them with their proper values from scope.
        var params = [];
        pathToRegexp(keyPath, params);
        var err;
        var parsedKeyPath = _.reduce(params, function(memoKeyPath, param) {
          if (err) { return false; }

          try {
            var paramMatchExpr = ':' + param.name;
            var actualParamValue = scope[param.name];
            if (!actualParamValue) {
              err = new Error(
                'Generator error:\n' +
                'A scope variable (`' + param.name + '`) was referenced in target: `' + memoKeyPath + '`,\n' +
                'but `' + param.name + '` does not exist in the generator\'s scope.'
              );
              return false;
            }
            actualParamValue = String(actualParamValue);

            return memoKeyPath.replace(paramMatchExpr, actualParamValue);
          } catch (e) {
            err = new Error('Generator error: Could not parse target key: ' + memoKeyPath);
            err.message = e;
            return false;
          }
        }, keyPath);
        if (!parsedKeyPath) { return proceed(err); }

        // Create path from `rootPath` to `keyPath` to use as the `rootPath`
        // for any generators or builtins in this target.
        // (use a copy so that child generators don't mutate the scope)
        var targetScope = _.merge({}, scope, {
          rootPath: path.resolve(scope.rootPath, parsedKeyPath),
          // Include reference to original keypath for error reporting
          keyPath: keyPath
        });



        // If `target` is an array, run each item
        if (_.isArray(target)) {
          async.eachSeries(target, function(targetItem, next) {
            generateTarget({
              target: targetItem,
              parent: Generator,
              scope: _.cloneDeep(targetScope),
              recursiveGenerate: helpGenerate
            }, next);
          }, proceed);//_∏_
          return;
        }//-•

        // Otherwise, just run the single target generator/helper
        generateTarget({
          target: target,
          parent: Generator,
          scope: targetScope,
          recursiveGenerate: helpGenerate
        }, proceed);

      }, // </async.each.iteratee>

      function afterwards(err) {
        if (err) {
          // If an error occurred running this generator, then we'll check
          // to see if the generator defined an `error` LC.  If not, then we'll
          // just go ahead and bail with the error.  But if it DID, then we'll
          // run the `error` LC first before bailing.
          if (!Generator.error) {
            return sb(err, scope, sb);
          }
          else {
            return Generator.error(err, scope, sb);
          }
        }

        //--•
        // If we made it here, we successfully ran the generator.
        //
        // Now, if the generator did NOT specify an `after` lifecycle callback,
        // then go ahead and bail.
        if (!Generator.after) { return sb(); }

        // --•
        // But otherwise it _did_ expose an `after` LC.
        // So we'll run that before passing back control.
        Generator.after(scope, sb);
        //</Generator.after() :: running the generator's `after` lifecycle callback>

      }); // </async.each()>

    } // </Generator.before -> success>
  })); // </Generator.before>

};
