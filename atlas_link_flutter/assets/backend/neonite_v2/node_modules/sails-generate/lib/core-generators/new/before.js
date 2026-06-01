/**
 * Module dependencies
 */

var util = require('util');
var path = require('path');
var fs = require('fs');
var chalk = require('chalk');
var _ = require('@sailshq/lodash');
var flaverr = require('flaverr');
var read = require('read');
var IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT = require('../../IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT');
var sailsGeneratePj = require('../../../package.json');

/**
 * before()
 *
 * Runs before this generator begins processing targets.
 *
 * @param  {Dictionary} scope
 * @param  {Function} done
 */

module.exports = function before (scope, done) {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // TIP: To easily experiment with `sails new`, try this:
  // https://github.com/balderdashy/sails-generate/commit/a7916a9eba5ef01f01043d590cf2f75845b2ab3c
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  var args0 = scope.args[0];

  // Use a reasonable default app name
  var defaultAppName = args0;

  // Handle `sails new` being called on the current directory (or with no arguments at all)
  // by using the current directory's base name as the default app name.
  // e.g. `sails new .` or `sails new` inside of `code/myApp` will create an app named `my-app`.
  if (defaultAppName === '.' || defaultAppName === './' || !defaultAppName) {
    defaultAppName = path.basename(process.cwd());
  }
  // Use the base name of the directory that the app will be in as its default name.
  // e.g. `sails new foo/bar/myApp` will create an app named `my-app` in the directory `foo/bar/myApp`.
  defaultAppName = _.kebabCase(path.basename(defaultAppName));

  // Make changes to the rootPath where the sails project will be created
  scope.rootPath = path.resolve(process.cwd(), args0 || '');

  // Potentially prompt about the nature of this new Sails app.
  (function(proceed){

    // If a more specific option was provided, then skip the prompt.
    if (scope.caviar !== undefined || scope.traditional !== undefined || scope.minimal !== undefined || scope.frontend !== undefined) {
      // console.log('skipped prompt', scope.caviar, scope.traditional, scope.minimal, scope.frontend);
      return proceed();
    }

    console.log(
      ' Choose a template for your new Sails app:'+'\n'+
      ' 1. '+chalk.bold.blue('Web App')+'  ·  Extensible project with auth, login, & password recovery\n'+ // kinda like ubuntu
      ' 2. '+chalk.bold.blue('Empty')+'    ·  An empty Sails app, yours to configure\n'+ // kinda like debian
      chalk.gray(' (type "'+chalk.bold('?')+'" for help, or <CTRL+C> to cancel)')
      // ' What kind of new Sails app would you prefer?'+'\n'+
      // ' What kind of new Sails app would you like?'+'\n'+
      // ' What kind of Sails app would you rather generate?'+'\n'+
      // ' This will generate a new Sails app at '+scope.rootPath+'.\n'+
      // ' Which sounds best?'+'\n'+
      // ' 1. '+chalk.bold.blue('Web Application')+'  ·  Standard project with auth, login, & password recovery\n'+ // kinda like ubuntu
      // ' 1. '+chalk.bold.blue('Web App')+'       ·  Extensible project with auth, login, & password recovery\n'+ // kinda like ubuntu
      // ' 1. '+chalk.bold.blue('Web App Essentials')+'       ·  Extensible starter app with auth, login, & password recovery\n'+ // kinda like ubuntu
      // ' 1. '+chalk.bold.blue('Web App')+'  ·  Extensible project with auth, login, & password recovery\n'+ // kinda like ubuntu
      // ' 1. '+chalk.bold.blue('Web App')+'  ·  An extensible starter app with auth, login, password recovery, & more\n'+ // kinda like ubuntu
      // ' 1. '+chalk.bold.blue('Web App')+'       ·  Extensible project with login, password recovery, etc '+chalk.gray('(recommended)')+'\n'+ // kinda like ubuntu
      // ' 2. '+chalk.bold.blue('Empty')+'         ·  An empty Sails app, yours to configure\n'+ // kinda like debian
      // ' 3. '+chalk.bold.blue('"Pure" API')+'    ·  Back-end only (no views, no assets)\n'+
      // ' 3. '+chalk.bold.blue('Pure API')+'      ·  Back-end only (no views, no assets)\n'+
      // ' 3. '+chalk.bold.blue('RESTful API')+'   ·  Back-end only (no views, no assets)\n'+
      // ' 4. '+chalk.bold.red ('Minimalist')+'    ·  Bare-bones Node.js server (no ORM, no nothin\')\n'
      // ' 8. '+chalk.bold.gray('Customize...')
      // ' 3. '+chalk.gray('What should I choose?')
      // ' 9. '+chalk.bold.gray('I\'m unsure')
    );
    read({ prompt: '?' }, function(err, result){
      if (err) {
        if (err.message === 'canceled'){
          return proceed(flaverr('E_CANCELED', new Error('Canceled the prompt in `sails new`')));
          // TODO: ^ handle that special error code at the top level in sails-generate's core
          // (e.g. `if (flaverr.taste('E_CANCELED')) {`)
        } else {
          return proceed(err);
        }
      }//•

      // console.log('got:',result);
      switch (result.toLowerCase()) {
        case '1':
        case 'web app':
        case 'w':
          scope.caviar = true;
          return proceed();
        case '2':
        case 'empty':
        case 'e':
        case '':
          scope.traditional = true;
          return proceed();
        case '3':
          scope.frontend = false;
          return proceed();
        case '4':
          scope.minimal = true;
          return proceed();
        case '?':
        case 'help':
        case 'h':
          console.log(chalk.bold.yellow('Choosing a template:'));
          // console.log('A framework is your app\'s DNA, but a template is like its upbringing.');
          console.log('| In older releases of the Sails framework, all new apps looked pretty much the same--');
          console.log('| but as of Sails v1.0, new apps come in a few different flavors, called "templates".');
          console.log('| The template you choose determines which files Sails will generate in your new project.');
          console.log('| (If you aren\'t sure which to pick, start by generating one of each to compare.)');
          console.log('|   [?] More info at https://sailsjs.com/support');
          return proceed(flaverr('E_CANCELED', new Error('Canceled the prompt in `sails new` in order to seek assistance online')));
        default:
          return proceed(new Error('Invalid choice: "'+result+'"'));
      }

    });//_∏_
  })(function(err) {
    if (err) { return done(err); }

    try {

      // Now set up defaults for the rest of our scope:
      var author = process.env.USER || 'anonymous node/sails user';

      var owner = author;

      _.defaults(scope, {

        // Specific to new Sails apps
        appName: defaultAppName,
        linker: true,
        adapter: 'sails-disk',
        without: [],
        traditional: true,
        caviar: false,
        generatedWithSailsVersion: scope.sailsPackageJSON.version,
        generatedWithSailsGenerateVersion: sailsGeneratePj.version,
        verbose: scope.verbose||false,

        // Generic
        // (for any generated Node package)
        IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT: IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT,
        author: author,
        owner: owner,
        year: (new Date()).getFullYear(),
        github: {
          username: author,
          owner: owner
        },
        modules: {},
        website: util.format('https://github.com/%s', owner)
      });

      // Expand `without` into an array.
      // (assumes it is a comma-separated list)
      if (_.isString(scope.without)) {
        scope.without = scope.without.split(',');

        // Strip empty strings just in case there is a trailing comma.
        scope.without = _.without(scope.without, '');

      }//>-

      // Validate `without`
      if (!_.isArray(scope.without)) {
        return done(new Error('Couldn\'t create a new Sails app.  The provided `without` option (`'+util.inspect(scope.without, {depth:null})+'`) is invalid.'));
      }//-•

      // To avoid confusion, disable the `async` dependency by default.
      if (!_.contains(scope.without, 'async')) {
        scope.without = _.uniq((scope.without||[]).concat(['async']));
      }

      // Provide a shortcut for generating an extremely minimal Sails app.
      if (scope.minimal) {
        scope.without = _.union(scope.without, ['i18n','orm','sockets','grunt','lodash','async','session','views']);
        scope.frontend = false;// FUTURE: replace --frontend option and instead implement the same thing as another kind of "--without".  e.g. "--without=frontend".  OR we may just be able to get rid of it altogether.
        delete scope.minimal;
      }//ﬁ


      // Handle `caviar` vs. `traditional`
      if (scope.caviar) {
        // `caviar` takes precedence over `traditional` and `minimal`
        scope.traditional = false;

        // Ensure there are no conflicts with disabled features vs. --caviar.
        if (scope.frontend === false || _.intersection(scope.without, ['orm', 'sockets', 'grunt', 'lodash', 'session', 'views']).length > 0) {
          return done(new Error('Invalid usage: Cannot generate a new app with the expanded feature set (`--caviar`) while also excluding some of the features that it needs.'));
        }

        // Override targets:
        scope.modules.layout = {
          targets: {
            './': { copy: 'views/caviar-layout.ejs' }
          }
        };
        scope.modules.homepage = {
          targets: {
            './': { copy: 'views/pages/caviar-homepage.ejs' }
          }
        };
        scope.modules['404'] = {
          targets: {
            './': { copy: 'views/404-caviar.ejs' }
          }
        };
        scope.modules['500'] = {
          targets: {
            './': { copy: 'views/500-caviar.ejs' }
          }
        };
      } else if (scope.traditional === false) {
        // remember, at this point, "scope.minimal" should have already been taken care of above.
        return done(new Error('Invalid usage: Cannot set `traditional: false` without providing some other flag (e.g. `caviar: true`)'));
      } else {
        // If `caviar` is not enabled, then don't run the "parasails" sub-generator.
        scope.modules['parasails'] = false;

        // And don't generate .htmlhintrc or .lesshintrc files.
        scope.modules['.htmlhintrc'] = false;
        scope.modules['.lesshintrc'] = false;
      }


      // Reject unrecognized "without" entries
      var LEGAL_WITHOUT_IDENTIFIERS = ['lodash', 'async', 'orm', 'sockets', 'grunt', 'i18n', 'session', 'views'];
      var unrecognizedEntries = _.difference(scope.without, LEGAL_WITHOUT_IDENTIFIERS);
      if (unrecognizedEntries.length > 0) {
        return done(new Error('Couldn\'t create a new Sails app.  The provided `without` option contains '+(unrecognizedEntries.length===1?'an':unrecognizedEntries.length)+' unrecognized entr'+(unrecognizedEntries.length===1?'y':'ies')+': '+unrecognizedEntries));
      }//-•

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // Note: An earlier version of `onlyIf` support was implemented here, but
      // then moved into core in f324b8763a7a62510310ea636dc815c0b629f6ad and removed
      // from here in the following commit.
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


      // --without=views
      //
      // Don't include the `views/` folder, or the `config/views.js`
      // and `config/security.js` files, or HTML and LESS-specific syntax files.
      if (_.contains(scope.without, 'views')) {
        scope.modules['views'] = false;
        scope.modules['config/views.js'] = false;
        scope.modules['config/security.js'] = false;
        scope.modules['.htmlhintrc'] = false;
        scope.modules['.lesshintrc'] = false;
      }//-•

      // --without=session
      //
      // Don't include the `config/session.js` file, and don't include policies
      // directory or the policies config file.
      // (while policies work fine without a session, the default policy doesn't
      // make sense without one, and generating an empty folder without a gitkeep
      // would be weird.)
      if (_.contains(scope.without, 'session')) {
        scope.modules['config/session.js'] = false;
        scope.modules['config/policies.js'] = false;
        scope.modules['api/policies'] = false;
      }//-•

      // --without=i18n
      //
      // Don't include the `config/locales/` directory if this is being generated
      // without `i18n`.  Also don't include `config/i18n.js`.
      if (_.contains(scope.without, 'i18n')) {
        scope.modules['config/locales/de.json'] = false;
        scope.modules['config/locales/en.json'] = false;
        scope.modules['config/locales/es.json'] = false;
        scope.modules['config/locales/fr.json'] = false;
        scope.modules['config/i18n.js'] = false;
      }//-•

      // --without=grunt
      //
      // Don't include the `tasks/` directory or Gruntfile.js if this is being generated
      // without `grunt`.  Also don't include `assets/`.
      if (_.contains(scope.without, 'grunt')) {
        scope.modules.grunttasks = false;
        scope.modules.gruntfile = false;
        scope.modules.assets = false;
        scope.modules.layout = {
          targets: {
            './': { copy: 'views/gruntless-layout.ejs' }
          }
        };
      }//-•

      // --without=sockets
      //
      // If this is being generated without `sockets`, do a different, stripped-down homepage instead.
      if (_.contains(scope.without, 'sockets')) {
        scope.modules.homepage = {
          targets: {
            './': { copy: 'views/stripped-down-homepage.ejs' }
          }
        };

        scope.modules['config/sockets.js'] = false;
        scope.modules['sails.io.js'] = false;
      }

      // --without=orm
      //
      if (_.contains(scope.without, 'orm')) {
        scope.modules.homepage = {
          targets: {
            './': { copy: 'views/stripped-down-homepage.ejs' }
          }
        };
        scope.modules['config/models.js'] = false;
        scope.modules['config/datastores.js'] = false;
        scope.modules['api/models'] = false;
        scope.modules['api/models/.gitkeep'] = false;

        // Also disable blueprints
        scope.modules['config/blueprints.js'] = false;
      }

      // Prevent individual sub-generators from logging their "afterwards" log message.
      scope.suppressFinalLog = true;

      // --------------------------------------------------------------------------------------------------------------
      // > FUTURE: convert this to work based on `--without` instead (e.g. you'd be able to do --without=lodash,async,frontend)
      // (but note this generator needs to be grepped for the word "frontend" first - there are other places in here where `scope.frontend` is used!!!)

      // Alias for `--no-front-end` or `--front-end`
      // (instead of "--no-frontend" or "--frontend")
      if (!_.isUndefined(scope['front-end'])) {
        scope.frontend = scope['front-end'];
        delete scope['front-end'];
      }

      // If this is an app being generated with `--no-frontend` (which is equivalent
      // to `--frontend=false`), then disable some of our targets.
      //
      if (scope.frontend === false) {
        scope.modules.frontend = false;
        scope.modules.gruntfile = false;
        scope.modules.views = false;
        scope.modules.views = false;
        scope.modules['sails.io.js'] = false;
        scope.modules['.htmlhintrc'] = false;
        scope.modules['.lesshintrc'] = false;
      }//>-
      // --------------------------------------------------------------------------------------------------------------

      // Ensure there aren't any insurmountable conflicts at the generator's root path.
      // > This is so that we don't inadvertently delete anything, unless the `force`
      // > flag was enabled.
      (function _ensureNoInsurmountableConflictsAtRootPath(proceed){

        // Try to read a list of the direct children of this directory.
        var dirContents;
        try {

          dirContents = fs.readdirSync(scope.rootPath);

        }
        catch (errFromReadDirSync) {

          switch (errFromReadDirSync.code) {

            // If the directory doesn't exist, no sweat.  (We'll keep going.)
            case 'ENOENT':
              return proceed();

            // If the target path is actually a file, instead of a directory,
            // then we'll check to see if the `force` flag was enabled.  If not,
            // then we'll bail with a fatal error.  But if `force` WAS enabled,
            // then we'll go ahead and continue onwards.
            case 'ENOTDIR':
              if (scope.force) {
                return proceed();
              }//-•
              return proceed(flaverr('alreadyExists', new Error('Couldn\'t create a new Sails app at "'+scope.rootPath+'" because something other than an empty directory already exists at that path.')));

            // Otherwise, there was some other issue, so bail w/ a fatal error.
            default:
              return proceed(new Error('Couldn\'t create a new Sails app at "'+scope.rootPath+'" because an unexpected error occurred: '+errFromReadDirSync.stack));

          }//</switch :: errFromReadDirSync.code>
        }//</catch :: errFromReadDirSync>

        //--•
        // If this directory is empty, then we're good.
        if (dirContents.length === 0){
          return proceed();
        }

        //--•
        // But otherwise, this directory is NOT empty.

        // If the `force` flag is enabled, we can proceed.
        // (Otherwise we have to fail w/ a fatal error.)
        if (scope.force) {
          return proceed();
        } else { return proceed(flaverr('alreadyExists', new Error('Couldn\'t create a new Sails app at "'+scope.rootPath+'" because a non-empty directory already exists at that path.'))); }

      })(function (err){
        if (err) {
          switch (err.code) {
            case 'alreadyExists': return done(err);
            default: return done(err);
          }
        }

        return done();

      });//</self-calling function :: ensure there aren't any insurmountable conflicts at the generator's root path>
    } catch (err) { return done(err); }
  });//_∏_  (potentially prompted)

};
