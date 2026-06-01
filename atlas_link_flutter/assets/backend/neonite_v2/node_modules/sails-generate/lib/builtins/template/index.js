/**
 * Module dependencies
 */

var util = require('util');
var path = require('path');
var _ = require('@sailshq/lodash');
var fsx = require('fs-extra');
var reportback = require('reportback')();
var generateFile = require('../file');



/**
 * Read an `ejs` template, compile it using scope.
 * Then use `file` helper to write it to its destination.
 *
 * @option {String}    rootPath
 * @option {String}    templatePath
 * @option {Boolean}   force[=false]
 *
 * @sb.success
 * @sb.error
 * @sb.alreadyExists
 * @sb.noTemplate
 */

module.exports = function(options, sb) {
  sb = reportback.extend(sb, {
    noTemplate: 'error',
    alreadyExists: 'error'
  });

  // console.log('In templatehelper for :',options.rootPath);

  if (_.isUndefined(options.rootPath) || !_.isString(options.rootPath)) {
    return sb.invalid(new Error('Consistency violation: `rootPath` is a required string (got `'+options.rootPath+'`)'));
  }
  if (_.isUndefined(options.templatePath) || !_.isString(options.templatePath)) {
    return sb.invalid(new Error('Consistency violation: `templatePath` is a required string (got `'+options.templatePath+'`)'));
  }
  if (_.isUndefined(options.templatesDirectory) || !_.isString(options.templatesDirectory)) {
    return sb.invalid(new Error('Consistency violation: `templatesDirectory` is a required string (got `'+options.templatesDirectory+'`)'));
  }

  // Compute the canonical path to a template
  // given its relative path from its source generator's
  // `templates` directory.
  var absTemplatePath = path.resolve(options.templatesDirectory, options.templatePath);

  fsx.readFile(absTemplatePath, 'utf8', function(err, originalTemplate) {
    if (err) {

      // Ensure we have an Error instance.
      err = _.isError(err) ? err : new Error(err);

      // err.message = 'Template error: ' + err.message;
      // err.path = absTemplatePath;
      if (err.code === 'ENOENT') {
        return sb.noTemplate(new Error('No such template exists at `'+absTemplatePath+'`.  Details:'+err.stack));
      }

      return sb(new Error('Template error: '+err.stack));
    }

    //--•

    // Render the dynamic file contents.
    var renderedStr;
    try {

      var precompiledTemplateFn = _.template(originalTemplate);

      // Don't pass in `options._`, which is automatically provided from CLI parsing.
      // (if present, it messes up lodash's availability in templates)
      var templateData = _.omit(options, '_');

      // But DO expose `util`, for convenience.
      templateData.util = util;

      // Render the template + data into a string.
      renderedStr = precompiledTemplateFn(templateData);

    } catch (e) {
      // console.log('Lodash version:', _.VERSION);
      var prettifiedUnderlyingError = util.inspect(e, {depth: null});
      return sb(new Error('Generator failed to compile one of its template (`'+options.templatePath+'`):\n'+prettifiedUnderlyingError));
    }

    // Generate file on disk.
    return generateFile(_.extend(options, {
      contents: renderedStr
    }), sb);

  });//</fsx.readFile()>

};
