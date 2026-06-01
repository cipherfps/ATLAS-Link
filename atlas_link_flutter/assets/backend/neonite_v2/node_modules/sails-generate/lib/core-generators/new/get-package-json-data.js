/**
 * Module dependencies
 */

var path = require('path');
var util = require('util');
var _ = require('@sailshq/lodash');
var flaverr = require('flaverr');
var IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT = require('../../IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT');



/**
 * getPackageJsonData()
 *
 * Get the data that will be encoded in the
 * newly-generated `package.json` file.
 *
 * @param  {Dictionary} scope
 * @returns {Dictionary}
 */
module.exports = function getPackageJsonData(scope) {

  var sailsPkg;
  if (_.isObject(scope.sailsPackageJSON)) {
    sailsPkg = scope.sailsPackageJSON;
  }
  else if (_.isString(scope.sailsRoot)) {
    sailsPkg = require(path.resolve(scope.sailsRoot, 'package.json'));
  }
  else {
    throw new Error('Could not load package.json from Sails itself.  Make sure either `sailsPackageJSON` or `sailsRoot` are being passed in to `sails-generate`.');
  }

  // To determine the SVR for the sails dep. in the newly created package.json file,
  // base it off of the `version` specified in the package.json of Sails itself.
  var sailsSVR = '^' + sailsPkg.version;

  var GRUNT_DEP_SVR = '1.0.4';
  var SAILS_HOOK_GRUNT_DEP_SVR = '^5.0.0';

  // List default dependencies used for apps with a frontend
  // > Note: If this app is being generated with --caviar, we shuffle some deps
  // > and include a few extras.
  var declaredDeps = {

    // Sails core
    'sails': sailsSVR,

    // Have to have this if grunt hook is included, because it's required as a local dep
    // in order to use grunt programmatically.  (Hopefully we can change this in Grunt
    // at some point, if you want to help, please contact ben)
    //
    // Note that for caviar, we pull it into the dev dependencies.
    'grunt': !scope.caviar ? GRUNT_DEP_SVR : undefined,

    // External hooks
    'sails-hook-apianalytics': scope.caviar ? '^2.0.6' : undefined,
    'sails-hook-grunt': !scope.caviar ? SAILS_HOOK_GRUNT_DEP_SVR : undefined,//« FUTURE: potential changes here for non-caviar apps too (see https://sailsjs.com/roadmap)
    'sails-hook-organics': scope.caviar ? '^3.0.0' : undefined,//« (formerly `sails-stdlib`)
    'sails-hook-orm': '^4.0.3',
    'sails-hook-sockets': '^3.0.0',

    // Production stuff
    '@sailshq/connect-redis': '^6.1.3',
    '@sailshq/socket.io-redis': '^6.1.2',

    // Lodash
    '@sailshq/lodash': scope.lodashSVR || '^3.10.6',

    // Async
    'async': scope.asyncSVR || '2.6.4'

  };


  // If this is an app being generated with `--without=lodash`, then exclude the Lodash dep.
  if (_.contains(scope.without, 'lodash')) {
    delete declaredDeps['@sailshq/lodash'];
  }//>-

  // If this is an app being generated with `--without=async`, then exclude the related dep(s).
  if (_.contains(scope.without, 'async')) {
    delete declaredDeps.async;
  }//>-

  // If this is an app being generated with `--without=orm`, then exclude the related dep(s).
  if (_.contains(scope.without, 'orm')) {
    delete declaredDeps['sails-hook-orm'];
  }//>-

  // If this is an app being generated with `--without=sockets`, then exclude the related dep(s).
  if (_.contains(scope.without, 'sockets')) {
    delete declaredDeps['sails-hook-sockets'];
    delete declaredDeps['@sailshq/socket.io-redis'];
  }//>-

  // FUTURE: extrapolate session hook

  // If this is an app being generated with `--without=grunt`, then exclude the related dep(s).
  if (_.contains(scope.without, 'grunt')) {
    delete declaredDeps['sails-hook-grunt'];
    delete declaredDeps.grunt;
  }//>-


  // If this is an app being generated with `--no-frontend`, then include only
  // the bare minimum, esp. excluding grunt and all grunt-related dependencies.
  if (scope.frontend === false) {
    declaredDeps = _.pick(declaredDeps, [
      'sails',
      'sails-hook-orm',
      'sails-hook-sockets',
      '@sailshq/lodash',
      'async'
    ]);
  }//>-

  var currentNodeMajorVersionAsNumber = +(process.version.match(/^v([^.]+)\.([^.]+)\./)[1]);
  var currentNodeMinorVersionAsNumber = +(process.version.match(/^v([^.]+)\.([^.]+)\./)[2]);
  // (^^Used below)

  // Creating default package.json file content
  var defaultPackageJSONContent = {
    name: scope.appName,
    private: true,
    version: '0.0.0',
    description: scope.description || 'a Sails application',
    keywords: [],
    dependencies: declaredDeps,
    devDependencies: {
      // Everyone should use this:
      'eslint': '5.16.0',

      // Caviar only:
      'htmlhint': scope.caviar? '0.11.0': undefined,// « FUTURE: Explore options w/ ejslint (https://www.npmjs.com/package/ejs-lint)
      'lesshint': scope.caviar? '6.3.6': undefined,
      // Thanks to the deploy script, these next two can be devDeps instead
      // of normal dependencies:
      grunt: scope.caviar? GRUNT_DEP_SVR: undefined,
      'sails-hook-grunt': scope.caviar? SAILS_HOOK_GRUNT_DEP_SVR: undefined,

    },
    scripts: {
      start:
        'NODE_ENV=production node app.js',
      test: (
        'npm run lint && npm run custom-tests && echo \'Done.\''
        // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
        // FUTURE: Same deal as below:
        // ```
        // './node_modules/sails/bin/test',  # (e.g. same as running `sails test`)
        // ```
        // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      ),
      lint: (
        scope.caviar? (
          './node_modules/eslint/bin/eslint.js . --max-warnings=0 --report-unused-disable-directives && '+
          'echo \'✔  Your .js files look so good.\' && '+
          './node_modules/htmlhint/bin/htmlhint -c ./.htmlhintrc views/*.ejs && ./node_modules/htmlhint/bin/htmlhint -c ./.htmlhintrc views/**/*.ejs && ./node_modules/htmlhint/bin/htmlhint -c ./.htmlhintrc views/**/**/*.ejs && ./node_modules/htmlhint/bin/htmlhint -c ./.htmlhintrc views/**/**/**/*.ejs && ./node_modules/htmlhint/bin/htmlhint -c ./.htmlhintrc views/**/**/**/**/*.ejs && ./node_modules/htmlhint/bin/htmlhint -c ./.htmlhintrc views/**/**/**/**/**/*.ejs && ./node_modules/htmlhint/bin/htmlhint -c ./.htmlhintrc views/**/**/**/**/**/**/*.ejs && '+
          'echo \'✔  So do your .ejs files.\' && '+
          './node_modules/lesshint/bin/lesshint assets/styles/ --max-warnings=0 && '+
          'echo \'✔  Your .less files look good, too.\''
        ) : (
          './node_modules/eslint/bin/eslint.js . --max-warnings=0 --report-unused-disable-directives && '+
          'echo \'✔  Your .js files look good.\''
        )

        // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
        // FUTURE: Set up something like:
        // ```
        // './node_modules/sails/bin/lint',  # (e.g. same as running `sails lint`)
        // ```
        // In order to do all this:  (without cluttering up the default package.json)
        // ```
        // 'echo && '+
        // 'echo "* * * * * * * * * * * * * * * * * * * * * * * * * * * " && '+
        // 'echo "Verifying code quality..." && '+
        // 'echo "* * * * * * * * * * * * * * * * * * * * * * * * * * * " && '+
        // 'echo && '+
        // 'if ! node ./node_modules/eslint/bin/eslint.js -v '+
        // '; then '+
        //   'echo && '+
        //   'echo && '+
        //   'echo "- - -" && '+
        //   'echo "✘  Could not check code quality." && '+
        //   'echo "Looks like something went wrong trying to access \'eslint\'." && '+
        //   'echo "|  If you are not sure what to do next, try:" && '+
        //   'echo "|  npm install eslint --save-dev --save-exact" && '+
        //   'echo "|  " && '+
        //   'echo "|  And then give this another go:" && '+
        //   'echo "|  npm test" && '+
        //   'echo &&'+
        //   'exit 1'+
        // '; else '+
        //   'npm run lint && '+
        //   'echo && '+
        //   'node ./node_modules/eslint/bin/eslint . --max-warnings=0 && '+
        //   'echo \'✔  OK!\' && '+
        //   'echo'+
        // '; fi && '+
        // 'echo',
        // ```
        // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      ),
      'custom-tests': (
        'echo "(No other custom tests yet.)" && echo'
        // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
        // FUTURE: Same deal here:
        // ```
        // './node_modules/sails/bin/test',  # (e.g. same as running `sails test custom`)
        // ```
        // For this stuff:
        // ```
        // 'echo && '+
        // 'echo "* * * * * * * * * * * * * * * * * * * * * * * * * * * " && '+
        // 'echo "Running custom tests..." && '+
        // 'echo "* * * * * * * * * * * * * * * * * * * * * * * * * * * " && '+
        // 'echo && '+
        // 'echo && '+
        // 'echo "- - -" && '+
        // 'echo "✘  Could not run custom tests." && '+
        // 'echo "No custom tests are set up for this project yet." && '+
        // 'echo "|  To set up your own tests for your API, replace the \'custom-tests\' script" && '+
        // 'echo "|  in your package.json file so that it runs Mocha and/or Postman instead of logging" && '+
        // 'echo "|  this message." && '+
        // 'echo &&'+
        // 'exit 1',
        // ```
        // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      ),

      // Only include the boilerplate deploy script if --caviar is in use.
      deploy: (
        scope.caviar?
        'echo \'This script assumes a dead-simple, opinionated setup on Heroku.\' && echo \'But, of course, you can deploy your app anywhere you like.\' && echo \'(Node.js/Sails.js apps are supported on all modern hosting platforms.)\' && echo && echo \'Warning: Specifically, this script assumes you are on the master branch, and that your app can be deployed simply by force-pushing on top of the *deploy* branch.  It will also temporarily use a local *predeploy* branch for preparing assets, that it will delete after it finishes.  Please make sure there is nothing you care about on either of these two branches!!!\' && echo \'\' && echo \'\' && echo \'Preparing to deploy...\' && echo \'--\' && git status && echo \'\' && echo \'--\' && echo \'I hope you are on the master branch and have everything committed/pulled/pushed and are completely up to date and stuff.\' && echo \'********************************************\'  && echo \'** IF NOT THEN PLEASE PRESS <CTRL+C> NOW! **\' && echo \'********************************************\' && echo \'Press CTRL+C to cancel.\' && echo \'(you have five seconds)\' && sleep 1 && echo \'...4\' && sleep 1 && echo \'...3\' && sleep 1 && echo \'...2\' && sleep 1 && echo \'...1\' && sleep 1  && echo \'\' && echo \'Alright, here we go.  No turning back now!\' && echo \'Trying to switch to master branch...\' && git checkout master && echo && echo \'OK.  Now wiping node_modules/ and running npm install...\' && rm -rf node_modules && rm -rf package-lock.json && npm install && (git add package-lock.json && git commit -am \'AUTOMATED COMMIT: Did fresh npm install before deploying, and it caused something relevant (probably the package-lock.json file) to change!  This commit tracks that change.\' || true) && echo \'Deploying as version:\' && npm version patch && echo \'\' && git push origin master && git push --tags && (git branch -D predeploy > /dev/null 2>&1 || true) && git checkout -b predeploy && (echo \'Now building+minifying assets for production...\' && echo \'(Hang tight, this could take a while.)\' && echo && node node_modules/grunt/bin/grunt buildProd || (echo && echo \'------------------------------------------\' && echo \'IMPORTANT!  IMPORTANT!  IMPORTANT!\' && echo \'ERROR: Could not compile assets for production!\' && echo && echo \'Attempting to recover automatically by stashing, \' && echo \'switching back to the master branch, and then \' && echo \'deleting the predeploy branch... \' && echo && echo \'After this, please fix the issues logged above\' && echo \'and push that up.  Then, try deploying again.\' && echo \'------------------------------------------\' && echo && echo \'Staging, deleting the predeploy branch, and switching back to master...\' && git stash && git checkout master && git branch -D predeploy && false)) && mv www .www && git add .www && node -e \'sailsrc = JSON.parse(require(\"fs\").readFileSync(\"./.sailsrc\", \"utf8\"));  if (sailsrc.paths&&sailsrc.paths.public !== undefined || sailsrc.hooks&&sailsrc.hooks.grunt !== undefined) { throw new Error(\"Cannot complete deployment script: .sailsrc file has conflicting contents!  Please throw away this midway-complete deployment, switch back to your original branch (master), remove the conflicting stuff from .sailsrc, then commit and push that up.\"); }  sailsrc.paths = sailsrc.paths || {};  sailsrc.paths.public = \"./.www\";   sailsrc.hooks = sailsrc.hooks || {};  sailsrc.hooks.grunt = false;  require(\"fs\").writeFileSync(\"./.sailsrc\", JSON.stringify(sailsrc))\' && git commit -am \'AUTOMATED COMMIT: Automatically bundling compiled assets as part of deploy, updating the EJS layout and .sailsrc file accordingly.\' && git push origin predeploy && git checkout master && git push origin +predeploy:deploy && git push --tags && git branch -D predeploy && git push origin :predeploy && echo \'\' && echo \'--\' && echo \'OK, done.  It should be live momentarily on your staging environment.\' && echo \'(if you get impatient, check the Heroku dashboard for status)\' && echo && echo \'Staging environment:\' && echo \' 🌐–•  https://staging.example.com\' && echo \'       (hold ⌘ and click to open links in the terminal)\' && echo && echo \'Please review that to make sure it looks good.\' && echo \'When you are ready to go to production, visit your pipeline on Heroku and press the PROMOTE TO PRODUCTION button.\''
        : undefined
      ),

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // FUTURE: Maybe bring this back as an opt-in thing.
      // (For some users, it is more confusing than it is helpful)
      // ```
      // debug: (
      //   'node debug app.js'
      // )
      // ```
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    },
    main: 'app.js',
    repository: {
      type: 'git',
      url: util.format('git://github.com/%s/%s.git', scope.github.username, scope.appName)
    },
    author: scope.author || '',
    license: scope.license || '',
    engines: {
      node: (
        // Guess compatibility based on the current Node version of the process running
        // the generator.  Loosen range to tolerate up to the end of the current LTS major
        // version (or the next LTS major version, if generating process is not LTS.)
        //
        // ...but going beyond that, since Node.js maintains a commitment to backwards-compatibility
        // even across major versions (https://nodejs.org/en/about/releases/#majors), it's
        // reasonable to remove the version cap.  The version with the cap is left commented
        // out here for future reference:
        // ```
        // currentNodeMajorVersionAsNumber % 2 === 0?
        // '>='+currentNodeMajorVersionAsNumber+'.'+currentNodeMinorVersionAsNumber+' '+'<'+(currentNodeMajorVersionAsNumber+1)//«LTS
        // : '>='+currentNodeMajorVersionAsNumber+'.'+currentNodeMinorVersionAsNumber+' '+'<'+(currentNodeMajorVersionAsNumber+2)//«non-LTS
        // ```
        // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
        // FUTURE: maybe do something smarter here to take Node core prereleases into account
        // for the semver range.  e.g. if the Node process running this generator is on a
        // prerelease version of Node, there could be significant differences in feature support.
        // In that case, we should probably lock the semver range to that precise Node version,
        // prerelease (`-foo`, `-4`, etc) and all.
        // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
        '^'+currentNodeMajorVersionAsNumber+'.'+currentNodeMinorVersionAsNumber
      )
    }
  };

  if (currentNodeMajorVersionAsNumber < 4) {
    console.error();
    console.error('------------------------------------------------------------------------------------------');
    console.error('It looks like your current version of Node.js is '+process.version+'.');
    console.error('We\'re sorry, but to build an app with Sails 1.0 you must use at least Node version 4.');
    console.error('To get the most out of Sails, we recommend Node version 7.9 or greater.');
    console.error();
    console.error(' [?] If you\'re unsure or want advice, swing by https://sailsjs.com/support');
    console.error('------------------------------------------------------------------------------------------');
    throw flaverr({
      name: 'CompatibilityError',
      code: 'E_NODE_VERSION_TOO_LOW',
      message: 'Node version too low (needs Node v4 or greater).'
    });
  }//•

  if(scope.caviar && !IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT) {
    console.error();
    console.error('------------------------------------------------------------------------------------------');
    console.error('It looks like your current version of Node.js is '+process.version+'.');
    console.error('We\'re sorry, but to build on top of Sails 1.0\'s expanded starter app, you must');
    console.error('use Node version 7.9 or greater.  Please upgrade your version of Node, or generate');
    console.error('a traditional Sails app instead.');
    console.error();
    console.error(' [?] If you\'re unsure or want advice, swing by https://sailsjs.com/support');
    console.error('------------------------------------------------------------------------------------------');
    throw flaverr({
      name: 'CompatibilityError',
      code: 'E_NODE_VERSION_TOO_LOW',
      message: 'Node version too low for expanded starter app (needs Node v7.9 or greater).'
    });
  }

  if(!IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT) {
    console.warn();
    console.warn('------------------------------------------------------------------------------------------');
    console.warn('It looks like your current version of Node.js is '+process.version+'.');
    console.warn();
    console.warn('Sails works with all officially-supported versions of Node.js.');
    console.warn('But it works *especially* well with Node versions 7.9 and up.');
    console.warn();
    console.warn('As of Sails v1.0, your app can now take advantage of the new `await` keyword,');
    console.warn('instead of relying on callbacks or promise chaining (`.exec()`, `.then()`, etc.)');
    console.warn('This new feature of Sails/Node.js/JavaScript makes your team more productive,');
    console.warn('and it usually leads to more stable code with fewer bugs.');
    console.warn();
    console.warn('If you choose *not* to upgrade Node.js, you\'ll still be able to use Sails (of course!)');
    console.warn('But we really recommend taking a moment to look into this.  It\'s fast and easy, and ');
    console.warn('we think you\'ll find it helps you build higher quality apps, faster than ever before.');
    console.warn();
    console.warn('Upgrade @ https://sailsjs.com/upgrading');
    console.warn();
    console.warn(' [?] If you\'re unsure or want advice, swing by https://sailsjs.com/support');
    console.warn('------------------------------------------------------------------------------------------');
    console.warn();
  }//ﬁ


  //
  // Check for `packageJson` configuration
  //

  if (scope.packageJson && _.isObject(scope.packageJson)) {
    //
    // Adding new dependencies to package.json
    //
    _.merge(defaultPackageJSONContent, (scope.packageJson || {}));

    //
    // Remove dependencies that has false as version
    // If somebody don't need dependency it could be removed using passing to scope:
    //
    // ```
    // packageJson: {
    //    dependencies: {
    //      ejs: false
    //    }
    // }
    // ```
    //
    if (scope.packageJson.dependencies) {
      defaultPackageJSONContent.dependencies = _.omit(defaultPackageJSONContent.dependencies, function(value) {
        return value === false;
      });
    }
  }

  return _.defaults(scope.appPackageJSON || {}, defaultPackageJSONContent);
};
