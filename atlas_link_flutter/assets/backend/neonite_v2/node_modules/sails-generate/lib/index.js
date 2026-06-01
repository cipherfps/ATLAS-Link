/**
 * Module dependencies
 */

var util = require('util');
var _ = require('@sailshq/lodash');
var reportback = require('reportback')();
var loadGeneratorDef = require('./load-generator-def');
var helpGenerate = require('./help-generate');


/**
 * sails-generate
 *
 * Generate files and folders using builtins,
 * or run other generators.
 *
 * @param  {Dictionary} scope
 * @param  {Function} cb
 *         @property {Function} log.info
 *         @property {Function} log.error
 *         @property {Function} error
 *         @property {Function} invalid
 */

module.exports = function sailsGen (scope, cb) {
  cb = cb || {};

  cb = reportback.extend(cb, {
    error: cb.error,
    invalid: cb.invalid,
    success: function() {
      cb.log.info('ok!');
    },
    notSailsApp: function() {
      cb.log.error('Not a sails app.');
    },
    alreadyExists: function() {
      return cb.error('Already exists.');
    }
  });

  // `scope.generatorType` is a required string.
  if (!scope.generatorType) {
    return cb.invalid(new Error('Sorry, `scope.generatorType` must be defined and truthy.'));
  }
  if (!_.isString(scope.generatorType)) {
    return cb.invalid(new Error('Sorry, `scope.generatorType` must be a string.'));
  }

  // If specified, `scope.modules` must be a dictionary.
  if (!_.isUndefined(scope.modules)) {
    if (!_.isObject(scope.modules) || _.isArray(scope.modules) || _.isFunction(scope.modules)) {
      return cb.invalid(new Error('Invalid `scope.modules`:  Should be a dictionary, but instead got: '+util.inspect(scope.modules, {depth: null})));
    }
  }


  // Before doing anything else, set `scope.topLvlRootPath` to be the current value of `rootPath`.
  // (If rootPath is undefined, use `process.cwd()`)
  if (!_.isUndefined(scope.rootPath)) {
    scope.topLvlRootPath = scope.rootPath;
  }
  else {
    scope.topLvlRootPath = process.cwd();
  }


  // Try to require the appropriate generator of this type.
  var generatorDef;
  try {

    generatorDef = loadGeneratorDef({
      modules: scope.modules,
      generatorType: scope.generatorType,
      topLvlRootPath: scope.topLvlRootPath
    });

  } catch (e) {
    switch (e.code) {

      // If it could not be loaded, give up as `invalid`.
      case 'generatorNotFound':
        // console.log('DEBUG:::GENERATOR NOT FOUND');
        return cb.invalid(e);

      // If an unexpected fatal error occurred, handle it.
      default: return cb(e);

    }
  }//</catch>
  //--•

  // IWMIH, we found our generator.  So now let's use it.
  helpGenerate(generatorDef, scope, cb);

};
