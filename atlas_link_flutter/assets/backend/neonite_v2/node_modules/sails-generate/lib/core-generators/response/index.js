/**
 * Module dependencies
 */

var path = require('path');
var _ = require('@sailshq/lodash');


// On initial require of this file:
//
// • Determine abs path to templates folder.
var TEMPLATES_PATH = path.resolve(__dirname,'./templates');


/**
 * sails-generate-response
 *
 * Usage:
 * `sails generate response <resource>`
 *
 * @type {Dictionary}
 */
module.exports = {


  templatesDirectory: TEMPLATES_PATH,


  targets: {

    './api/responses/:filename': { template: 'response.template' }

  },


  /**
   * This `before()` function is run before generating targets.
   * It validates user input, configures defaults, gets extra
   * dependencies, etc.
   *
   * @param  {Dictionary} scope
   * @param  {Function} sb    [callback]
   */
  before: function(scope, sb) {

    // Make sure we're in the root of a Sails project.
    var pathToPackageJSON = path.resolve(scope.rootPath, 'package.json');
    var invalidPackageJSON;
    try {
      require(pathToPackageJSON);
    } catch (unused) {
      invalidPackageJSON = true;
    }

    if (invalidPackageJSON) {
      return sb.invalid('Sorry, this command can only be used in the root directory of a Sails project.');
    }
    if (!scope.rootPath) {
      return sb.invalid('Usage: sails generate response <responsename>');
    }

    // scope.args are the raw command line arguments.
    //
    // e.g. if you run:
    // sails generate response serverError bar baz
    // then:
    // scope.args = ['serverError', 'bar', 'baz']
    //
    _.defaults(scope, {
      id: scope.args[0]
    });


    if (!scope.id) {
      return sb.invalid('Usage: sails generate response <responsename>');
    }


    if (scope.coffee || scope.lang === 'coffee' || scope.ext === '.coffee') {
      console.warn('WARNING: CoffeeScript is not supported for this generator.  Proceeding anyway...');
    }


    // Derive appropriate filename
    if (_.isUndefined(scope.filename)) {
      scope.filename = scope.id + '.js';
    }

    // Trigger callback with no error to proceed.
    return sb();

  }//</before>

};

