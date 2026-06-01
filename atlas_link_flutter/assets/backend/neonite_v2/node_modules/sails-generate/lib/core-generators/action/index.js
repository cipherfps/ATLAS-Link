/**
 * Module dependencies
 */

var path = require('path');
var _ = require('@sailshq/lodash');
var builtinTemplate = require('../../builtins/template');
var inventDescription = require('../../invent-description');
var IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT = require('../../IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT');


/**
 * sails-generate-action
 *
 * Usage:
 * `sails generate action <name>`
 *
 * @type {Dictionary}
 */

module.exports = {


  //  ╔╗ ╔═╗╔═╗╔═╗╦═╗╔═╗
  //  ╠╩╗║╣ ╠╣ ║ ║╠╦╝║╣
  //  ╚═╝╚═╝╚  ╚═╝╩╚═╚═╝ooo
  before: function (scope, done){

    var roughName;

    // Use actions2 by default, since actions are being generated individually.
    if (scope.actions2 === undefined) {
      scope.actions2 = true;
    }

    // The default template to use.
    scope.templateName = 'actions2.template';

    // If `--no-actions2` was used, switch the default template and easter-egg template suffix.
    if (!scope.actions2) {
      scope.templateName = 'action.template';
    }

    // Accept --name
    if (scope.name) {
      roughName = scope.name;
    }
    // Or otherwise the first serial arg is the "roughName" of the action we want to create.
    else if (_.isArray(scope.args)) {

      // If more than one serial args were provided, they'll constitute the action friendly name
      // and we'll combine them to form the base name.
      if (scope.args.length >= 2) {
        // However, note that we first check to be sure no dots or slashes were used
        // (if so, this would throw things off)
        if (scope.args[0].match(/[\/\.\\]/)) {
          return done(new Error(
            'Too many serial arguments: A "." or "/" was specified in the name for this new action, but extra words were provided too.\n' +
            '(should be provided like either `foo-bar/baz/view-profile` or `View profile`).'
          ));
        }

        scope.friendlyName = scope.args.join(' ');
        roughName = _.camelCase(scope.friendlyName);
      }
      // Otherwise, we'll infer an appropriate friendly name further on down, and just use the
      // first serial arg as our "roughName".
      else if (scope.args[0] && _.isString(scope.args[0])) {
        roughName = scope.args[0];
      }

    }//>-

    if (!roughName) {
      return done(new Error(
        'Missing argument: Please provide a name for the new action.\n' +
        '(should be "verby" and use the imperative mood; e.g. `view-profile` or `sign-up`).'
      ));
    }

    // Replace backslashes with proper slashes.
    // (This is crucial for Windows compatibility.)
    roughName = roughName.replace(/\\/g, '/');

    // Now get our actionName.
    // Be kind -- transform slashes to dots when creating the actionName.
    scope.actionName = roughName.replace(/\/+/g, '.');
    // Then split on dots and make sure each segment is using camel-case before recombining.
    // (We'll unwind this later for most of the things.)
    scope.actionName = _.map(scope.actionName.split('.'), function (segment){
      return _.camelCase(segment);
    }).join('.');

    // After transformation, the actionName must contain only letters, numbers, and dots--
    // and start with a lowercased letter.
    if (!scope.actionName.match(/^[a-z][a-zA-Z0-9\.]*$/)) {
      return done( new Error('The name `' + scope.actionName + '` is invalid. '+
                           'Action names must start with a lower-cased letter and contain only '+
                           'letters, numbers, and dots.'));
    }

    // If the action name contains something like "FooController", then simplify that.
    scope.actionName = scope.actionName.replace(/(\.?)(.+)controller\./i, '$1$2.');

    // Then get our `relPath` (filename / path).
    // When building the relPath, we convert any dots to slashes.
    scope.relPath = scope.actionName.replace(/\.+/g, '/');
    // Then split on slashes and make sure each segment is using kebab-case before recombining.
    scope.relPath = _.map(scope.relPath.split('/'), function (segment){
      // One exception: Don't kebab-case words like "v1" within this segment, if any.
      return _.map(_.words(segment), function(word){
        if (word.match(/[a-z]+[0-9]+/)) { return word; }
        return _.kebabCase(word);
      }).join('-');
    }).join('/');
    // (And of course, finally, we tack on `.js` at the end-- we're not barbarians after all.)
    scope.relPath += '.js';

    // Grab the filename for potential use in our template.
    scope.filename = path.basename(scope.relPath);


    // Identify the action "stem" for use below.
    // (e.g. "view-stuff-and-things" from "v1.pages.view-stuff-and-things")
    var stem = _.last(scope.actionName.split('.'));
    var sentenceCaseStem = _.map(_.words(stem), function (word, i){ if (i===0) { return _.capitalize(word); } else { return word[0].toLowerCase() + word.slice(1); } }).join(' ');

    // Attempt to invent a description, if there isn't one already.
    if (_.isUndefined(scope.description)) {
      scope.description = inventDescription(scope.actionName, true);
    }//>-

    // Infer other defaults.
    _.defaults(scope, {
      friendlyName: scope.friendlyName || sentenceCaseStem,
      description: scope.description || '',
      inferredViewTemplatePath: '',
      verbose: false,
      IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT: IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT,
      // getAlternativeTemplate: null << FUTURE: a configurable function
    });



    //  ┌┐ ┬ ┬┬┬ ┌┬┐  ┬┌┐┌  ┌─┐┌─┐┌┬┐┬┌─┐┌┐┌┌─┐  ┌─┐┬─┐┌─┐┌┬┐  ┬ ┬┌─┐┌─┐┬┌─┌─┐
    //  ├┴┐│ │││  │───││││  ├─┤│   │ ││ ││││└─┐  ├┤ ├┬┘│ ││││  ├─┤│ ││ │├┴┐└─┐
    //  └─┘└─┘┴┴─┘┴   ┴┘└┘  ┴ ┴└─┘ ┴ ┴└─┘┘└┘└─┘  └  ┴└─└─┘┴ ┴  ┴ ┴└─┘└─┘┴ ┴└─┘

    // SECURITY HOOK
    // ================================================
    // FUTURE: If the specified relative path is "security/grant-csrf-token", then make an assumption and go
    // ahead and generate a simple exampl override of the corresponding built-in action from the `security` hook.

    // BLUEPRINTS HOOK
    // ================================================
    // FUTURE: If action stem is "find", and the name of a resource can be inferred from the specified relative
    // path, then make an assumption and go ahead and generate a reified version of the corresponding blueprint action.

    // FUTURE: If action stem is "findOne", and the name of a resource can be inferred from the specified relative
    // path, then make an assumption and go ahead and generate a reified version of the corresponding blueprint action.

    // FUTURE: If action stem is "create", and the name of a resource can be inferred from the specified relative
    // path, then make an assumption and go ahead and generate a reified version of the corresponding blueprint action.

    // FUTURE: If action stem is "update", and the name of a resource can be inferred from the specified relative
    // path, then make an assumption and go ahead and generate a reified version of the corresponding blueprint action.

    // FUTURE: If action stem is "destroy", and the name of a resource can be inferred from the specified relative
    // path, then make an assumption and go ahead and generate a reified version of the corresponding blueprint action.



    //  ┌─┐┌┬┐┬ ┬┌─┐┬─┐  ┌─┐┬┌┬┐┌─┐┬  ┌─┐  ┌┬┐┬┌┬┐┌─┐  ┌─┐┌─┐┬  ┬┌─┐┬─┐┌─┐
    //  │ │ │ ├─┤├┤ ├┬┘  └─┐││││├─┘│  ├┤    │ ││││├┤───└─┐├─┤└┐┌┘├┤ ├┬┘└─┐
    //  └─┘ ┴ ┴ ┴└─┘┴└─  └─┘┴┴ ┴┴  ┴─┘└─┘   ┴ ┴┴ ┴└─┘  └─┘┴ ┴ └┘ └─┘┴└─└─┘

    // ACTION THAT SERVES A WEB PAGE
    // ================================================
    // If action stem begins with "view" (and if it's not just... "view" by itself--
    // which would be weird, but whatever), then make an assumption about what to generate.
    // (set up the success exit with `viewTemplatePath` ready to go)
    if (stem.match(/^view/i) && stem !== 'view') {
      // console.log('stem!',_.words(stem).slice(1));
      var inferredViewTemplateBasename = _.reduce(_.words(stem).slice(1), function (memo, segment){
        // One exception: Don't kebab-case stuff like "v1".
        if (segment.match(/[a-z]+[0-9]+/)) {
          memo += segment;
        }
        else {
          memo += _.kebabCase(segment);
        }

        // Attach a hyphen at the end, if there isn't one already.
        memo = memo.replace(/\-*$/, '-');

        return memo;
      }, '');

      // Trim the last hyphen off the end.
      inferredViewTemplateBasename = inferredViewTemplateBasename.replace(/\-*$/, '');
      // console.log('inferredViewTemplateBasename!',inferredViewTemplateBasename);

      // If this action is in a subdirectory, apply that subdirectory to our inferred
      // view template path:
      var intermediateSubdirs = scope.actionName.split('.');
      intermediateSubdirs.pop();
      // console.log('intermediateSubdirs', intermediateSubdirs);
      intermediateSubdirs = intermediateSubdirs.map(function(subdirName){
        // One exception: Don't kebab-case words like "v1" within this subdir name, if any.
        return _.map(_.words(subdirName), function(word){
          if (word.match(/[a-z]+[0-9]+/)) { return word; }
          return _.kebabCase(word);
        }).join('-');
      });//∞

      scope.inferredViewTemplatePath = (
        path.join('pages/', intermediateSubdirs.join('/'), inferredViewTemplateBasename)
        .replace(/\\/g,'/')//« because Windows
      );

      // Adjust description:
      scope.description = (function _gettingAdjustedDescription(){
        var words = _.words(sentenceCaseStem).slice(1);
        if (_.last(words).match(/page/i)){
          words = words.slice(0, -1);
        }
        var friendlyPageName = words.join(' ');
        if (friendlyPageName.length > 1) {
          friendlyPageName = friendlyPageName[0].toUpperCase() + friendlyPageName.slice(1);
        }
        return 'Display "'+friendlyPageName+'" page.';
      })();//= (†)
    }//>-

    // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    // Note: For an example of how to swap out the template dynamically
    // (e.g. to inject smarter defaults based on context, or fun easter eggs)
    // take a look at the approach here:
    // https://github.com/balderdashy/sails-generate/commit/9b8cb6e85bdcc8b19f51976cd3a395d4b2512161
    // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


    return done();

  },


  //  ╔═╗╔═╗╔╦╗╔═╗╦═╗
  //  ╠═╣╠╣  ║ ║╣ ╠╦╝
  //  ╩ ╩╚   ╩ ╚═╝╩╚═ooo
  after: function (scope, done) {

    if (!scope.suppressFinalLog) {
      // Disable the "Created a new …!" output so we can use our own instead.
      scope.suppressFinalLog = true;

      if (scope.actions2) {
        var stem = _.last(scope.actionName.split('.'));

        // Make some guesses about how to build an appropriate route for this action:
        var httpMethodGuess;
        var pathPrefixGuess;
        var isProbablyOptimizedForSocketRequests;
        if (stem.match(/^(find|search|count|check|determine|validate|fetch|navigate|get)/i)) {
          httpMethodGuess = 'GET';
          pathPrefixGuess = '/api/v1';
        } else if (stem.match(/^(subscribe|listen)/i) || stem.match(/and-(subscribe|listen)$/i)) {
          httpMethodGuess = 'GET';
          pathPrefixGuess = '/api/v1';
          isProbablyOptimizedForSocketRequests = true;
        } else if (stem.match(/^(download|stream)/i)) {
          httpMethodGuess = 'GET';
          pathPrefixGuess = '';
        } else if (stem.match(/^(view|show)/i)) {
          httpMethodGuess = 'GET';
          pathPrefixGuess = '';
        } else if (stem.match(/^redirect/i) || stem.match(/or-redirect$/i) || stem.match(/and-redirect$/i)) {
          httpMethodGuess = 'GET';
          pathPrefixGuess = '';
        } else if (stem.match(/^(destroy|remove|archive|detach|unlink|delete)/i)) {
          httpMethodGuess = 'DELETE';
          pathPrefixGuess = '/api/v1';
        } else if (stem.match(/^(update|modify|edit|adjust|tweak|patch)/i)) {
          httpMethodGuess = 'PATCH';
          pathPrefixGuess = '/api/v1';
        } else {
          httpMethodGuess = 'POST';
          pathPrefixGuess = '/api/v1';
        }

        console.log();
        console.log('Successfully generated:');
        console.log(' •-','api/controllers/'+scope.relPath);
        console.log();
        console.log('A few reminders:');
        console.log(' (1)  For most projects, you\'ll need to manually configure an explicit route');
        console.log('      in your `config/routes.js` file; e.g.');
        console.log('          \''+httpMethodGuess+' '+pathPrefixGuess+'/'+scope.relPath.replace(/\.js$/,'')+'\': { action: \''+(
          scope.relPath.replace(/\\/g,'/')//« because Windows
          .replace(/\.js$/,'')
        )+'\''+(isProbablyOptimizedForSocketRequests ? ', isSocket: true' : '')+' },');
        console.log();
        console.log(' (2)  If you are using the built-in JavaScript SDK ("Cloud") for AJAX requests');
        console.log('      from client-side code, then after configuring a new route, you\'ll want to');
        console.log('      regenerate the SDK setup file using:');
        console.log('          sails run rebuild-cloud-sdk');
        console.log();
        console.log(' (3)  This new action was generated in the "actions2" format.');
        console.log('        [?] https://sailsjs.com/docs/concepts/actions');
        console.log();
        console.log(' (4)  Last but not least, since adding an action or route is a backend change,');
        console.log('      don\'t forget to re-lift the server before testing!');
        console.log();
      }
      else {
        done.log.info('Created a traditional (req,res) controller action, but as a standalone file.');
      }
    }

    return done();
  },



  //  ╔╦╗╔═╗╦═╗╔═╗╔═╗╔╦╗╔═╗
  //   ║ ╠═╣╠╦╝║ ╦║╣  ║ ╚═╗
  //   ╩ ╩ ╩╩╚═╚═╝╚═╝ ╩ ╚═╝
  targets: {

    './api/controllers/:relPath': {
      exec: function(scope, done) {
        scope.templatePath = './' + scope.templateName;
        builtinTemplate(scope, function(err) {
          if (err) {
            return done(err);
          }
          return done();
        });
      }
    }

  },


  //  ╔╦╗╔═╗╔╦╗╔═╗╦  ╔═╗╔╦╗╔═╗╔═╗  ╔╦╗╦╦═╗╔═╗╔═╗╔╦╗╔═╗╦═╗╦ ╦
  //   ║ ║╣ ║║║╠═╝║  ╠═╣ ║ ║╣ ╚═╗   ║║║╠╦╝║╣ ║   ║ ║ ║╠╦╝╚╦╝
  //   ╩ ╚═╝╩ ╩╩  ╩═╝╩ ╩ ╩ ╚═╝╚═╝  ═╩╝╩╩╚═╚═╝╚═╝ ╩ ╚═╝╩╚═ ╩
  templatesDirectory: path.resolve(__dirname,'./templates'),

};
