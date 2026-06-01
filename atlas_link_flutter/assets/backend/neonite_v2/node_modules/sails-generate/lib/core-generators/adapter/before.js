/**
 * Module dependencies
 */

var util = require('util');
var path = require('path');
var _ = require('@sailshq/lodash');


// The default semver range to use when generating files related
// to WAT (waterline-adapter-tests) and adapter spec API version compatibility.
var WATERLINE_ADAPTER_TESTS_SVR = '^1.0.0-6';
var ADAPTER_SPEC_VERSION = 1;


/**
 * This `before` function is run before generating targets.
 * Validate, configure defaults, get extra dependencies, etc.
 *
 * @param  {Dictionary} scope
 * @param  {Function} cb    [callback]
 */

module.exports = function(scope, cb) {

  //
  // scope.args are the raw command line arguments.
  //
  // e.g. if you run:
  // sails generate controlller user find create update
  // then:
  // scope.args = ['user', 'find', 'create', 'update']
  //


  // Look at arguments and set path to adapters (i.e. `:adapterPath`)
  if (scope.args) {
    if (scope.args[0]) {

      if (!scope.adapterType) {
        scope.adapterType = scope.args[0];
      }

      // Determine path to adapters
      var DEFAULT_ADAPTERS_PATH = scope.standalone ? '.' : 'api/adapters';
      scope.adapterPath = path.join(DEFAULT_ADAPTERS_PATH, scope.adapterType);
    }
  }

  // Use `adapterType` instead of `adapterName` if it's specified.
  scope.adapterName = scope.adapterType || scope.adapterName;
  scope.adapterType = scope.adapterType || scope.adapterName;
  scope.globalID = scope.adapterName+'Adapter';
  scope.identity = _.kebabCase(scope.adapterName);

  //
  // Validate custom scope variables which
  // are required by this generator.
  //

  if (!scope.adapterType) {
    return cb(new Error(
      'Missing argument: Please provide an `adapterType` for the new adapter.\n' +
      '(should refer to the type of database/webservice/thing it connects to; e.g. `mysql` or `irc`).'
    ));
  }

  // Determine default values based on the available scope.
  // (Taking multiple "passes" if necessary.)
  _.defaults(scope, {
    github: _.defaults(scope.github || {}, {
      // i.e.
      // Would you mind telling me your username on GitHub?
      // (or favorite pseudonym)
      username: process.env.USER || ''
    }),
    year: (new Date()).getFullYear(),

    // Waterline adapter tests (WAT) semver range
    waterlineAdapterTestsSVR: WATERLINE_ADAPTER_TESTS_SVR,

    // Waterline adapter spec API version
    adapterApiVersion: ADAPTER_SPEC_VERSION,

  });

  _.defaults(scope, {
    website: util.format('http://github.com/%s', scope.github.username),
    author: util.format('%s', scope.github.username) || 'a node.js/sails user',
    license: 'MIT',
    repository: _.defaults(scope.repository || {}, {
      type: 'git',
      url: util.format('git://github.com/%s/sails-%s.git', scope.github.username, scope.adapterType)
    })
  });


  // Determine an appropriate package name.
  // (Use a scoped package name if we have a github username)
  if (scope.github.username) {
    scope.packageName = ('@'+scope.github.username+'/' + 'sails-'+scope.adapterType.replace(/^sails-/,'')).toLowerCase();
  }
  else {
    scope.packageName = ('sails-'+scope.adapterType.replace(/^sails-/,'')).toLowerCase();
  }


  // Trigger callback with no error to proceed.
  return cb();

};
