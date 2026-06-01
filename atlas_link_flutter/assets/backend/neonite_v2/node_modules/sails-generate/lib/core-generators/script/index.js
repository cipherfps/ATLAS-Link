/**
 * Module dependencies
 */

var path = require('path');
var _ = require('@sailshq/lodash');
var inventDescription = require('../../invent-description');
var IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT = require('../../IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT');


/**
 * sails-generate-script
 *
 * Usage:
 * `sails generate script <name>`
 *
 * @type {Dictionary}
 */

module.exports = {


  //  ╔╗ ╔═╗╔═╗╔═╗╦═╗╔═╗
  //  ╠╩╗║╣ ╠╣ ║ ║╠╦╝║╣
  //  ╚═╝╚═╝╚  ╚═╝╩╚═╚═╝ooo
  before: function (scope, done){


    var roughName;

    // Accept --name
    if (scope.name) {
      roughName = scope.name;
    }
    // Or otherwise the first serial arg is the "roughName" of the shell script we want to create.
    else if (_.isArray(scope.args)) {

      // If more than one serial args were provided, they'll constitute the shell script friendly name
      // and we'll combine them to form the base name.
      if (scope.args.length >= 2) {
        // However, note that we first check to be sure no dots or slashes were used
        // (if so, this would throw things off)
        if (scope.args[0].match(/[\/\.]/)) {
          return done(new Error(
            'Too many serial arguments: A "." or "/" was specified in the name for this new shell script, but extra words were provided too.\n' +
            '(should be provided like either `db.lookups.get-search-results` or `Get search results`).'
          ));
        }
        scope.friendlyName = scope.args.join(' ');
        roughName = _.camelCase(scope.friendlyName);
      }
      // Otherwise, we'll infer an appropriate friendly name further on down. and just use the
      // first serial arg as our "roughName".
      else if (scope.args[0] && _.isString(scope.args[0])) {
        roughName = scope.args[0];
      }

    }//>-

    if (!roughName) {
      return done(new Error(
        'Missing argument: Please provide a name for the new shell script.\n' +
        '(should be "verby" and use the imperative mood; e.g. `send-reminders` or `import-legacy-org`).'
      ));
    }

    // Now get our scriptName.
    scope.scriptName = roughName;

    // Then split on slashes and make sure each segment is using kebab-case before recombining.
    scope.scriptName = _.map(scope.scriptName.split('/'), function (segment){
      return _.kebabCase(segment);
    }).join('/');

    // After transformation, the scriptName must contain only letters, numbers, and dashes--
    // and start with a lowercased letter.
    if (!scope.scriptName.match(/^[a-z][a-zA-Z0-9\-]*$/)) {
      return done( new Error('The name `' + scope.scriptName + '` is invalid. '+
                           'Shell script names must start with a lower-cased letter and contain only '+
                           'letters, numbers, and dashes.'));
    }

    // Then get our `relPath` (filename / path).
    // When building the relPath, we convert any dots to slashes.
    scope.relPath = scope.scriptName.replace(/\.+/g, '/');
    // Then split on slashes and make sure each segment is using kebab-case before recombining.
    scope.relPath = _.map(scope.relPath.split('/'), function (segment){
      // One exception: Don't kebab-case words like "v1" within this subdir name, if any.
      return _.map(_.words(segment), function(word){
        if (word.match(/[a-z]+[0-9]+/)) { return word; }
        return _.kebabCase(word);
      }).join('-');
    }).join('/');
    // (And of course, finally, we tack on `.js` (or `.coffee`) at the end-- we're not barbarians after all.)
    scope.relPath += scope.coffee ? '.coffee' : '.js';

    // Grab the filename for potential use in our template.
    scope.filename = path.basename(scope.relPath);

    // Identify the script "stem" for use below.
    // (e.g. "get-stuff-and-things" from "db.lookups.get-stuff-and-things")
    var scriptStem = _.last(scope.scriptName.split('.'));

    // Attempt to invent a description, if there isn't one already.
    if (_.isUndefined(scope.description)) {
      scope.description = inventDescription(scope.scriptName);
    }//>-

    _.defaults(scope, {
      friendlyName: scope.friendlyName || _.map(_.words(scriptStem), function (word, i){ if (i===0) { return _.capitalize(word); } else { return word[0].toLowerCase() + word.slice(1); } }).join(' '),
      description: scope.description || '',
      inferredSuccessOutputFriendlyName: '',
      lang: scope.coffee ? 'coffee' : 'js',
      verbose: false,
      IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT: IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT,
    });

    // If scriptStem begins with "get", then make an assumption about what to generate.
    // (set up the success exit with an inferred `outputFriendlyName`)
    if (scriptStem.match(/^get/i)) {
      var inferredNounPhraseWords = _.map(_.words(scriptStem).slice(1), function (word, i){ if (i===0) { return _.capitalize(word); } else { return word[0].toLowerCase() + word.slice(1); } });
      scope.inferredSuccessOutputFriendlyName = inferredNounPhraseWords.join(' ');
    }//>-

    // console.log('output friendly name:',scope.inferredSuccessOutputFriendlyName);
    // console.log('friendly name:',scope.friendlyName);

    return done();

  },


  //  ╔═╗╔═╗╔╦╗╔═╗╦═╗
  //  ╠═╣╠╣  ║ ║╣ ╠╦╝
  //  ╩ ╩╚   ╩ ╚═╝╩╚═ooo
  after: function (scope, done) {

    // Disable the "Created a new script!" output so we can use our own instead.
    scope.suppressFinalLog = true;
    console.log('Generated a new shell script!');
    console.log('–· '+path.join('scripts/', scope.relPath));
    console.log();
    console.log('(try it out with `sails run '+scope.scriptName+'`)');
    console.log();
    // console.log(' [?] Visit https://sailsjs.com/support for help.');
    // console.log('Try it:');
    // console.log('    sails run '+scope.scriptName);
    // console.log('Or:');
    // console.log('    sails run '+path.join('scripts/', scope.relPath));

    return done();
  },


  //  ╔╦╗╔═╗╦═╗╔═╗╔═╗╔╦╗╔═╗
  //   ║ ╠═╣╠╦╝║ ╦║╣  ║ ╚═╗
  //   ╩ ╩ ╩╩╚═╚═╝╚═╝ ╩ ╚═╝
  targets: {

    './scripts/:relPath': { template: 'script.template' }

  },


  //  ╔╦╗╔═╗╔╦╗╔═╗╦  ╔═╗╔╦╗╔═╗╔═╗  ╔╦╗╦╦═╗╔═╗╔═╗╔╦╗╔═╗╦═╗╦ ╦
  //   ║ ║╣ ║║║╠═╝║  ╠═╣ ║ ║╣ ╚═╗   ║║║╠╦╝║╣ ║   ║ ║ ║╠╦╝╚╦╝
  //   ╩ ╚═╝╩ ╩╩  ╩═╝╩ ╩ ╩ ╚═╝╚═╝  ═╩╝╩╩╚═╚═╝╚═╝ ╩ ╚═╝╩╚═ ╩
  templatesDirectory: path.resolve(__dirname,'./templates'),

};
