/**
 * Module dependencies
 */

var path = require('path');


/**
 * Usage:
 * `sails generate etc`
 *
 * @type {Dictionary}
 */

module.exports = {

  templatesDirectory: path.resolve(__dirname,'./templates'),

  targets: {
    './.gitignore':                  { copy: '../../../shared-templates/gitignore.template' },
    './.eslintrc':                   { template: '../../../shared-templates/eslintrc.template' },
    './.editorconfig':               { copy: '../../../shared-templates/editorconfig.template' },
    './.npmignore':                  { copy: '../../../shared-templates/npmignore.template' },
    './.travis.yml':                 { copy: '../../../shared-templates/travis.yml.template' },
    './appveyor.yml':                { copy: '../../../shared-templates/appveyor.yml.template' },
    './test/.eslintrc':              { copy: '../../../shared-templates/eslintrc-test-override.template' },
  },

  before: function (scope, done) {

    // Unless `force` was explicitly set to `false`, we'll set it to `true`.
    // (Most of the time, this generator is replacing pre-existing files.)
    if (scope.force !== false) {
      scope.force = true;
    }

    return done();
  },

  after: function (scope, done) {
    done.log.info('Replaced: `.gitignore`, `.editorconfig`, `.npmignore`, `.travis.yml`, & `appveyor.yml`.');
    done.log.warn('Before you commit these changes:');
    done.log.warn('Run `git diff` to make sure this didn\'t wipe out any important customizations!');
    return done();
  }

};
