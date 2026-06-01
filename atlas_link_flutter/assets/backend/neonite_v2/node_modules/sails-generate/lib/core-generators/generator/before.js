/**
 * Module dependencies
 */

var util = require('util');
var path = require('path');
var _ = require('@sailshq/lodash');


// Compatible Sails semver range.
var SAILS_SVR = '^1.0.0';


/**
 * Before generating targets...
 *
 * @param  {Dictionary}   scope
 * @param  {Function} done
 */
module.exports = function(scope, done) {

  // Look at arguments and adjust rootPath if necessary.
  if (scope.args) {

    if (scope.args[0]) {

      // Allow "type" to be specified as a CLI opt, for convenience.
      if (scope.type) {
        scope.generatorType = scope.type;
      }
      else {
        scope.generatorType = scope.args[0];
      }

      // Adjust rootPath to put the new generator in a new folder.
      scope.rootPath = path.resolve(scope.rootPath, 'sails-generate-'+_.kebabCase(scope.generatorType));

    }
  }


  if (!scope.generatorType) {
    return done(new Error(
      'Missing argument: Please provide a `generatorType` for this generator.\n' +
      '(should refer to the core generator to override, e.g. `controller` -- or a new generator to implement, e.g. `augmented-reality-server`).'
    ));
  }


  _.defaults(scope, {
    github: _.defaults(scope.github || {}, {
      // i.e.
      // Would you mind telling me your username on GitHub?
      // (or favorite pseudonym)
      username: process.env.USER || ''
    }),
    year: (new Date()).getFullYear(),
  });

  _.defaults(scope, {
    website: util.format('http://github.com/%s', scope.github.username),
    author: util.format('%s',scope.github.username) || 'a node.js/sails user',
    repository: _.defaults(scope.repository || {}, {
      type: 'git',
      url: util.format('git://github.com/%s/sails-generate-%s.git',scope.github.username, scope.generatorType)
    }),
    license: 'MIT',
    sailsSVR: SAILS_SVR
  });


  // Determine an appropriate package name.
  // (Use a scoped package name if we have a github username)
  if (scope.github.username) {
    scope.packageName = ('@'+scope.github.username+'/' + 'sails-generate-'+scope.generatorType).toLowerCase();
  }
  else {
    scope.packageName = ('sails-generate-'+scope.generatorType).toLowerCase();
  }

  return done();
};
