/**
 * Module dependencies
 */

var path = require('path');
var _ = require('@sailshq/lodash');
var fsx = require('fs-extra');
var reportback = require('reportback')();



/**
 * Copy file from one place to another.
 *
 * @required {String}  rootPath
 *           The absolute path of the destination for the copied file.
 *
 * @required {String}  templatePath
 *           The relative path from the generator's `templates/` dir
 *           to the source template whose contents will be copied.
 *
 * @required {String}  templatesDirectory
 *           An absolute path to the generator's `templates/` dir.
 *
 * @option {Boolean}   force[=false]
 *
 * @sb.success
 * @sb.error
 * @sb.alreadyExists
 * @sb.invalid
 */

module.exports = function(options, sb) {
  sb = reportback.extend(sb, {
    alreadyExists: 'error',
    invalid: 'error'
  });

  // Validate options and provide defaults.
  if (_.isUndefined(options.templatePath)) {
    return sb.invalid(new Error('Consistency violation: `templatePath` is required'));
  }
  if (_.isUndefined(options.templatesDirectory)) {
    return sb.invalid(new Error('Consistency violation: `templatesDirectory` is required'));
  }
  if (_.isUndefined(options.rootPath)) {
    return sb.invalid(new Error('Consistency violation: `rootPath` is required'));
  }
  _.defaults(options, {
    force: false
  });

  // Compute the absolute path to copy from, given its relative path
  // from its source generator's `templates/` directory.
  // > `templatesDirectory` should be provided as an absolute path!
  var absSrcPath = path.resolve(options.templatesDirectory, options.templatePath);

  // Note that we don't read in the file as utf8 here,
  // since it's not necessarily text (e.g. could be a binary file)
  //
  // So instead, we use fsx.copy(), which takes care of this for us.
  fsx.copy(absSrcPath, options.rootPath, {
    clobber: !!options.force
  }, function(err) {
    if (err) { return sb(err); }

    return sb();

  });//</fsx.copy()>

};
