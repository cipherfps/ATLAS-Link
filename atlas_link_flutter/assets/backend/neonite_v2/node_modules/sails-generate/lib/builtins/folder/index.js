/**
 * Module dependencies
 */

var path = require('path');
var _ = require('@sailshq/lodash');
var fsx = require('fs-extra');
var reportback = require('reportback')();




/**
 * Generate a folder
 *
 * @option {String} rootPath
 * @option {Boolean} gitkeep
 * [@option {Boolean} force=false]
 *
 * @sb [success]
 * @sb alreadyExists
 * @sb invalid
 * @sb error
 */
module.exports = function ( options, sb ) {

  // Provide default values for sb
  sb = reportback.extend(sb, {
    alreadyExists: 'error',
    invalid: 'error'
  });

  // Provide defaults and validate required options
  _.defaults(options, {
    force: false,
    gitkeep: false
  });
  var missingOpts = _.difference([
    'rootPath'
  ], Object.keys(options));
  if ( missingOpts.length ) {return sb.invalid(missingOpts);}


  var rootPath = path.resolve( process.cwd() , options.rootPath );


  // Only override an existing folder if `options.force` is true
  fsx.lstat(rootPath, function(err) {
    var exists = !(err && err.code === 'ENOENT');
    if (exists && err) {return sb.error(err);}

    if (exists && !options.force) {
      return sb.alreadyExists('Something else already exists at ::'+rootPath);
    }
    if (exists) {
      fsx.remove(rootPath, function deletedOldINode(err) {
        if (err) {return sb.error(err);}
        _afterwards_();
      });
    } else {_afterwards_();}

    function _afterwards_() {

      // Don't actually write the directory if this is a dry run.
      if (options.dry) {return sb.success();}

      // Create the directory
      fsx.mkdirs(rootPath, function directoryWasWritten(err) {
        if (err) {return sb.error(err);}
        // console.log('created dir at :::: ',rootPath);
        return sb.success();
      });
    }
  });
};
