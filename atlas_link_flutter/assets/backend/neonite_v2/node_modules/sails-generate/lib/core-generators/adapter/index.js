/**
 * sails-generate-adapter
 *
 * Usage:
 * `sails generate adapter`
 *
 * @type {Dictionary}
 */

module.exports = {

  templatesDirectory: require('path').resolve(__dirname,'./templates'),

  before: require('./before'),

  targets: {
    './:adapterPath': {folder: {}},
    './:adapterPath/README.md':                   { template: 'README.md' },
    './:adapterPath/.gitignore':                  { template: '../../../shared-templates/gitignore.template' },
    './:adapterPath/.eslintrc':                   { template: '../../../shared-templates/eslintrc.template' },
    './:adapterPath/.editorconfig':               { template: '../../../shared-templates/editorconfig.template' },
    './:adapterPath/.npmignore':                  { template: '../../../shared-templates/npmignore.template' },
    './:adapterPath/package.json':                { template: 'package.json.template' },
    './:adapterPath/test/run-standard-tests.js':  { template: 'test-templates/run-standard-tests.js' },
    './:adapterPath/index.js':                    { template: 'index.js.template' }
  }
};

