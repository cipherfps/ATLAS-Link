/**
 * Module dependencies
 */

var path = require('path');


/**
 * sails-generate-parasails
 *
 * (Re)generate parsails.js + Cloud SDK.
 *
 * Usage:
 * `sails generate parasails`
 *
 * @type {Dictionary}
 */

module.exports = {

  before: function(scope, done) {

    // This generator is intended to overwrite whatever files already exist at
    // these locations.
    scope.force = true;

    return done();

  },

  after: function(scope, done) {
    if (!scope.suppressFinalLog) {
      // Disable the "Created a new …!" output so we can use our own instead.
      scope.suppressFinalLog = true;

      console.log('Generated the latest recommended releases of parasails.js and cloud.js in `assets/dependencies/`.');
      console.log(' [?] For help: https://sailsjs.com/support');
    }

    return done();
  },

  // Set the templates directory to the `parasails` dependency's `dist/` folder.
  templatesDirectory: path.resolve(path.dirname(require.resolve('parasails')), 'dist/'),

  //  ╔╦╗╔═╗╦═╗╔═╗╔═╗╔╦╗╔═╗
  //   ║ ╠═╣╠╦╝║ ╦║╣  ║ ╚═╗
  //   ╩ ╩ ╩╩╚═╚═╝╚═╝ ╩ ╚═╝
  targets: {
    './assets/dependencies/parasails.js': { copy: 'parasails.js' },
    './assets/dependencies/cloud.js':     { copy: 'cloud.js' }
  }
};
