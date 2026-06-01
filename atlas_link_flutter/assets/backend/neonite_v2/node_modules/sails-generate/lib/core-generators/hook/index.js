/**
 * Module dependencies
 */

var path = require('path');
var _ = require('@sailshq/lodash');
var builtinTemplate = require('../../builtins/template');


/**
 * sails-generate-hook
 *
 * Usage:
 * `sails generate hook`
 *
 * @description Generates a hook
 * @help See https://sailsjs.com/docs/concepts/extending-sails/generators
 */

module.exports = {

  /**
   * `before()` is run before executing any of the `targets`
   * defined below.
   *
   * This is where we can validate user input, configure default
   * scope variables, get extra dependencies, and so on.
   *
   * @param  {Dictionary} scope
   * @param  {Function} cb    [callback]
   */

  before: function (scope, cb) {

    // scope.args are the raw command line arguments.
    //
    // e.g. if someone runs:
    // $ sails generate hook user find create update
    // then `scope.args` would be `['user', 'find', 'create', 'update']`
    if (!scope.args[0]) {
      return cb( new Error('Please provide a name for this hook.') );
    }

    // Attach defaults
    _.defaults(scope, {
      createdAt: new Date()
    });

    // Decide the output id for use in targets below:
    scope.id = scope.args[0];

    // Lop off the `sails-hook-` prefix for the hook name.
    scope.hookName = scope.id.replace(/^sails-hook-/, '');

    // Determine path to hook
    scope.hookPath = path.join(scope.standalone ? '.' : 'api/hooks', scope.id);

    // When finished, we trigger a callback with no error
    // to begin generating files/folders as specified by
    // the `targets` below.
    return cb();
  },



  /**
   * The files/folders to generate.
   * @type {Dictionary}
   */

  targets: {
    './:hookPath/index.js': { template: 'index.js.template' },
    // If using `--standalone`:
    './:hookPath/package.json': standaloneTemplate('./package.json.template'),
    './:hookPath/README.md': standaloneTemplate('./README.md.template'),
    './:hookPath/.gitignore': standaloneTemplate('../../../shared-templates/gitignore.template'),
    './:hookPath/.editorconfig': standaloneTemplate('../../../shared-templates/editorconfig.template'),
    './:hookPath/.npmignore': standaloneTemplate('../../../shared-templates/npmignore.template'),
    './:hookPath/.travis.yml': standaloneTemplate('../../../shared-templates/travis.yml.template'),
    './:hookPath/appveyor.yml': standaloneTemplate('../../../shared-templates/appveyor.yml.template'),
  },


  /**
   * The absolute path to the `templates` for this generator
   * (for use with the `template` helper)
   *
   * @type {String}
   */
  templatesDirectory: path.resolve(__dirname, './templates')

};

// Helper function to return an `exec` generator that only adds the given
// template if we're generating a standalone hook.
function standaloneTemplate(templatePath) {
  return {
    exec: function(scope, done) {
      // Only add this file if we're running in "standalone" mode.
      if (!scope.standalone) {
        return done();
      }
      scope.templatePath = templatePath;
      builtinTemplate(scope, done);
    }
  };
}


