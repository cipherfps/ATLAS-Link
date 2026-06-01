/**
 * Module dependencies
 */

var path = require('path');
var _ = require('@sailshq/lodash');
var fsx = require('fs-extra');
var reportback = require('reportback')();




/**
 * Generate a file using the specified string.
 *
 * @option {String} rootPath
 * @option {String} contents - the string contents to write to disk
 * [@option {Boolean} force=false]
 * [@option {Boolean} dry=false]
 *
 * @sb success
 * @sb error
 * @sb invalid
 * @sb alreadyExists
 */

module.exports = function(options, sb) {

  // provide default values for switchback
  sb = reportback.extend(sb, {
    alreadyExists: 'error'
  });


  // Validate options and provide defaults.
  if (_.isUndefined(options.contents)) {
    return sb.invalid(new Error('Consistency violation: `contents` is required'));
  }
  if (_.isUndefined(options.rootPath)) {
    return sb.invalid(new Error('Consistency violation: `rootPath` is required'));
  }
  _.defaults(options, {
    force: false
  });

  // In case we ended up here w/ a relative path,
  // resolve it using the process's CWD
  var rootPath = path.resolve(process.cwd(), options.rootPath);

  // Only override an existing file if `options.force` is true
  fsx.exists(rootPath, function(exists) {
    if (exists && !options.force) {
      return sb.alreadyExists('Something else already exists at ::' + rootPath);
    }

    // Don't actually write the file if this is a dry run.
    if (options.dry) { return sb.success(); }

    // Delete existing file if necessary
    (function _deleteExistingFileMaybe(proceed){
      if (!exists) { return proceed(); }

      fsx.remove(rootPath, function (err) {
        if (err) { return proceed(err); }
        return proceed();
      });

    })(function (err) {
      if (err) { return sb(err); }

      // console.log('about to generate a file @ `'+rootPath+'`:',options.contents);

      fsx.outputFile(rootPath, options.contents, function (err){
        if (err) { return sb(err); }

        return sb();

      });//</fsx.outputFile()>

    });//</self-calling function :: _deleteExistingFileMaybe()>

  });//</fsx.exists()>

};
