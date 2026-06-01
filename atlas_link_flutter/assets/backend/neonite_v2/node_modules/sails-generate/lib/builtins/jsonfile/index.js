/**
 * Module dependencies
 */

var path = require('path');
var _ = require('@sailshq/lodash');
var fsx = require('fs-extra');
var reportback = require('reportback')();



/**
 * Generate a JSON file
 *
 * @option {String} rootPath
 * @option {Dictionary} data
 * [@option {Boolean} force=false]
 *
 * @handlers success
 * @handlers error
 * @handlers alreadyExists
 */
module.exports = function jsonfile( options, handlers ) {

  // Provide default values for handlers
  handlers = reportback.extend(handlers, {
    alreadyExists: 'error'
  });

  // Provide defaults and validate required options
  _.defaults(options, {
    force: false
  });

  var missingOpts = _.difference([
    'rootPath',
    'data'
  ], Object.keys(options));
  if ( missingOpts.length ) {
    return handlers.invalid(new Error('Consistency violation: some required opts are missing: '+missingOpts));
  }


  var rootPath = path.resolve( process.cwd() , options.rootPath );

  // Only override an existing file if `options.force` is true
  fsx.exists(rootPath, function (exists) {
    if (exists && !options.force) {
      return handlers.alreadyExists('Something else already exists at ::'+rootPath);
    }

    if ( exists ) {
      fsx.remove(rootPath, function deletedOldINode (err) {
        if (err) { return handlers.error(err); }
        _afterwards_();
      });
    }
    else {_afterwards_();}

    function _afterwards_ () {
      fsx.outputJSON(rootPath, options.data, function (err){
        if (err) { return handlers.error(err); }
        else {handlers.success();}
      });
    }
  });
};
