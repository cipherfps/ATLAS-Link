/**
 * Module dependencies
 */

var _ = require('@sailshq/lodash');
var chalk = require('chalk');
var Process = require('machinepack-process');


/**
 * after()
 *
 * Runs after this generator has successfully finished
 * processing all of its targets.
 *
 * > Note: if any target fails, then the `error` LC runs instead.
 *
 *
 * @param  {Dictionary}   scope
 *
 *    @required {String}  rootPath
 *              The absolute path of the destination for the copied file.
 *
 *    @required {String}  sailsRoot
 *              The absolute path of the Sails dependency to grab installed
 *              dependencies from.
 *
 *    @required {String}  appName
 *              The name of the Sails app.
 *              (at this point, this is used purely for logging purposes).
 *
 *    @optional {Boolean}   fast[=false]
 *              If enabled, then dependencies for the newly-created app will
 *              will NOT be `npm install`-ed automatically.
 *
 *
 * @param  {Function} cb
 */

module.exports = function afterGenerate(scope, cb) {

  // Validate scope and provide defaults.
  if (_.isUndefined(scope.rootPath) || !_.isString(scope.rootPath)) {
    return cb(new Error('Consistency violation: `rootPath` is a required string.'));
  }
  if (_.isUndefined(scope.sailsRoot) || !_.isString(scope.sailsRoot)) {
    return cb(new Error('Consistency violation: `sailsRoot` is a required string.'));
  }
  if (_.isUndefined(scope.appName) || !_.isString(scope.appName)) {
    return cb(new Error('Consistency violation: `appName` is a required string.'));
  }

  _.defaults(scope, {

    // Whether to skip `npm installing deps automatically.
    fast: false,

  });



  // Skip installing dependencies if instructed by the `--fast` flag.
  if (scope.fast) {
    // FUTURE: use `path.basename(scope.rootPath)` for improved readability
    cb.log.info('Created a new Sails app `' + scope.appName + '`!');
    console.log(chalk.gray('(you will need to cd in and run `npm install`)'));
    return cb();
  }//--•


  // Otherwise IWMIH, we'll be automatically installing dependencies from NPM.

  // ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  // MAYBE just install the relevant deps.  It's a lot simpler this way.
  // (Note that we can prby just omit `sails`, since it'll automatically use the global version.)
  // ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  cb.log.info('Installing dependencies...');
  console.log(chalk.gray('Press CTRL+C to cancel.'));
  console.log(chalk.gray('(to skip this step in the future, use --fast)'));
  // console.log(chalk.gray('(if you do that, you\'ll need to cd in and run `rm -rf node_modules && npm install`)'));
  // console.log(chalk.gray(''));
  // console.log(chalk.gray('To skip this next time, use `sails new '+scope.appName+' --fast`.'));
  // console.log(chalk.gray('To skip this next time, use the --fast option.'));


  // Bind a SIGINT listener (i.e. CTRL+C)
  // > Note that this is defined as an inline function so that it works properly
  // > with `process.removeListener()`.
  var wasSigintTriggered;
  var sigintListener = function (){
    wasSigintTriggered = true;
    console.log();
    console.log();
    console.log(chalk.dim('------------------------------------------------------------'));
    console.log(chalk.yellow.bold('Cancelled `npm install`.'));
    console.log(chalk.white.bold('New app was generated successfully, but some dependencies'));
    console.log(chalk.white.bold('in node_modules/ are probably still incomplete or missing.'));
    console.log();
    console.log(chalk.white('Before you can lift this app, you\'ll need to cd in and run:'));
    console.log(chalk.white('    rm -rf node_modules && npm install'));
    console.log();
    console.log(chalk.gray('For more help, visit https://sailsjs.com/support.'));
    console.log();
  };
  process.once('SIGINT', sigintListener);

  // Install dependencies.
  Process.executeCommand({
    command: 'npm install',
    dir: scope.rootPath
  }).exec(function (err) {
    if (wasSigintTriggered) { return; }
    else {
      process.removeListener('SIGINT', sigintListener);
    }

    if (err) {
      console.log(chalk.dim('------------------------------------------------------------'));
      console.log(chalk.red.bold('Failed to install dependencies.'));
      console.log(chalk.white.bold('New app was generated successfully, but some dependencies'));
      console.log(chalk.white.bold('in node_modules/ are probably still incomplete or missing.'));
      console.log();
      console.log(chalk.white('Before you continue, please make sure you are connected to the'));
      console.log(chalk.white('internet, and that your NPM registry hasn\'t gone down.'));
      console.log(chalk.white('Then cd into the new app and run:'));
      console.log(chalk.white('    rm -rf node_modules && npm install'));
      console.log();
      console.log(chalk.gray('See below for complete error details.'));
      console.log(chalk.gray('For more help, visit https://sailsjs.com/support.'));
      console.log();
      return cb(err);
    }

    // SUCCESS!
    cb.log.info('Created a new Sails app `' + scope.appName + '`!');

    return cb();

  });//</ Process.executeCommand>

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // The above code replaced the old `npm install` implementation (including the bit
  // about symlinking for NPM <= v2).  For future reference, that original code can be
  // found here:
  // https://github.com/balderdashy/sails-generate/commits/57186db994fbf226cf14eb268ee0c9854efa81d8
  // https://github.com/balderdashy/sails-generate/commits/4f757316b9732d1cbff3d5705651cbc17233a23d
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

};
