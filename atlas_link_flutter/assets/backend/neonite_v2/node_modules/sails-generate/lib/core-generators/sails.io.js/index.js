/**
 * Module dependencies
 */

var path = require('path');
var _ = require('@sailshq/lodash');
var fsx = require('fs-extra');
var builtinCopy = require('../../builtins/copy');


/**
 * sails-generate-sails.io.js
 *
 * Usage:
 * `sails generate sails.io.js <location>`
 *
 * @type {Dictionary}
 */

module.exports = {

  before: function(scope, done) {

    // If this is being run as a child of the `new` generator, always put the file at assets/dependencies/sails.io.js.
    if (scope.generatorType === 'new') {
      scope.dest = path.resolve(scope.rootPath, 'assets', 'dependencies', 'sails.io.js');
    }

    // Otherwise if an explicit destination is given, use that.
    else if (_.isArray(scope.args) && scope.args[0]) {
      scope.dest = path.resolve(scope.topLvlRootPath, scope.args[0]);
    }

    // Otherwise see if we can locate the current location of `sails.io.js`.
    else {

      scope.dest = (function() {

        // Try the Sails 1.0 path.
        var pathToTry = path.resolve(scope.topLvlRootPath, 'assets', 'dependencies', 'sails.io.js');
        if (fsx.existsSync(pathToTry)) {
          return pathToTry;
        }
        // Try the pre-Sails-1.0 path.
        pathToTry = path.resolve(scope.topLvlRootPath, 'assets', 'js', 'dependencies', 'sails.io.js');
        if (fsx.existsSync(pathToTry)) {
          return pathToTry;
        }
        throw new Error('Could not automatically determine location of `sails.io.js` in your project.  Please specify it with `sails generate sails.io.js <destination>`.');

      })();

    }

    // This generator is intended to overwrite whatever sails.io.js they already have.
    scope.force = true;

    return done();

  },

  //  ╔╦╗╔═╗╦═╗╔═╗╔═╗╔╦╗╔═╗
  //   ║ ╠═╣╠╦╝║ ╦║╣  ║ ╚═╗
  //   ╩ ╩ ╩╩╚═╚═╝╚═╝ ╩ ╚═╝
  targets: {

    'sails.io.js': {
      exec: function(scope, done) {
        // Set the templates directory to the `sails.io.js-dist` dependency folder.
        scope.templatesDirectory = path.dirname(require.resolve('sails.io.js-dist'));
        // Set the template path to the `sails.io.js` file in that folder.
        scope.templatePath = 'sails.io.js';
        // Set the rootPath (the destination for the file) based on the `scope.dest` we determined above.
        scope.rootPath = scope.dest;
        // Copy the file.
        builtinCopy(scope, function(err) {
          if (err) {
            return done(err);
          }
          return done();
        });
      }
    }

  }
};
