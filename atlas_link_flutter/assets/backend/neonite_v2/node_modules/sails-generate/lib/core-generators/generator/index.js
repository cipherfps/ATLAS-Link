/**
 * sails-generate-generator
 *
 * Usage:
 * `sails generate generator :type`
 *
 * @scope {String} type    [required, type of generator to create]
 *
 * @type {Dictionary}
 */
module.exports = {

  templatesDirectory: require('path').resolve(__dirname,'./templates'),

  before: require('./before'),

  targets: {
    './index.js':           { template: 'index.js.template' },
    './README.md':          { template: 'README.md' },
    './.gitignore':         { template: '../../../shared-templates/gitignore.template' },
    './.editorconfig':      { template: '../../../shared-templates/editorconfig.template' },
    './.npmignore':         { template: '../../../shared-templates/npmignore.template' },
    './package.json':       { template: 'package.json.template' },
    './templates/.gitkeep': { template: '../../../shared-templates/gitkeep.template' },
  }
};
