/**
 * Module dependencies
 */

var fs = require('fs');
var path = require('path');
var util = require('util');
var _ = require('@sailshq/lodash');
var IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT = require('../../IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT');


// On initial require of this file:
//
// • Determine abs path to templates folder.
var TEMPLATES_PATH = path.resolve(__dirname,'./templates');
//
// • Fetch static template string for embedded action, and precompile it into a template function.
var EMBEDDED_ACTION_TEMPLATE_PATH = path.resolve(TEMPLATES_PATH, './embedded-action.template');
var EMBEDDED_ACTION_TEMPLATE_STR = fs.readFileSync(EMBEDDED_ACTION_TEMPLATE_PATH, 'utf8');
var EMBEDDED_ACTION_TEMPLATE_FN = _.template(EMBEDDED_ACTION_TEMPLATE_STR);


/**
 * sails-generate-controller
 *
 * Usage:
 * `sails generate controller <resource>`
 *
 * @type {Dictionary}
 */
module.exports = {


  templatesDirectory: TEMPLATES_PATH,


  targets: {

    './api/controllers/:filename': { template: 'controller.template' }

  },


  /**
   * This `before()` function is run before generating targets.
   * It validates user input, configures defaults, gets extra
   * dependencies, etc.
   *
   * @param  {Dictionary} scope
   * @param  {Function} cb    [callback]
   */
  before: function before(scope, cb) {

    // scope.args are the raw command line arguments.
    //
    // e.g. if you run:
    // sails generate controlller user find create update
    // then:
    // scope.args = ['user', 'find', 'create', 'update']
    //
    _.defaults(scope, {
      id: scope.args[0],
      actions: scope.args.slice(1),
      IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT: IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT,
    });


    //
    // Validate custom scope variables which
    // are required by this generator.
    //
    if (!scope.rootPath) {
      return cb.invalid('Usage: sails generate controller <controllername> [action ...]');
    }

    // Check that we're in a valid sails project
    // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    // FUTURE: see if we can remove this-- I think it's already been done by
    // Sails core at this point
    // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    var pathToPackageJSON = path.resolve(scope.rootPath, 'package.json');
    var invalidPackageJSON;
    try {
      require(pathToPackageJSON);
    } catch (unused) {
      invalidPackageJSON = true;
    }

    if (invalidPackageJSON) {
      return cb.invalid('Sorry, this command can only be used in the root directory of a Sails project.');
    }

    if (!scope.id) {
      return cb.invalid('Usage: sails generate controller <controllername> [action ...]');
    }

    if (_.endsWith(scope.id, '/')) {
      return cb.invalid('Controller name must not end in a slash.');
    }

    var trimmedControllerId;

    // Trim whitespace.
    trimmedControllerId = _.trim(scope.id);

    // Remove "Controller" or "Controller.js" suffix (if present).
    trimmedControllerId = scope.id.replace(/Controller$/, '');
    trimmedControllerId = scope.id.replace(/Controller\..*$/, '');
    if (!trimmedControllerId) {
      return cb.invalid('Invalid controller name:  "' + scope.id + '"');
    }//-•
    scope.id = trimmedControllerId;

    // Validate controller name
    // (this is by no means complete, just a quick pass in the interest of being helpful)
    var isControllerIdInvalid = scope.id.match(/[^\/a-zA-Z0-9\$]+/);
    if (isControllerIdInvalid) {
      return cb.invalid(
        'Invalid controller name:  "' + scope.id + '"'+'\n'+
        '(Stick to letters and numbers and you\'ll be golden.)'
      );
    }//-•

    // Validate optional action arguments
    var actions = scope.actions;
    var invalidActions = [];
    actions = _.map(actions, function(action) {

      // Validate action names
      // (this is by no means complete, just a quick pass in the interest of being helpful)
      var invalid = action.match(/[^a-zA-Z0-9_\$]+/);

      // Handle errors
      if (invalid) {
        return invalidActions.push(
          'Invalid action notation:   "' + action + '"');
      }
      return action;
    });

    // Handle invalid action arguments
    // Send back invalidActions
    if (invalidActions.length) {
      return cb.invalid(invalidActions);
    }

    // Make sure there aren't duplicates
    if ((_.uniq(actions)).length !== actions.length) {
      return cb.invalid('Duplicate actions not allowed!');
    }


    // Determine the "entity" for this controller.
    // This expects strings like `pet`, but it also tolerates `foo/bar/pet`
    // > (in either case, the entity would be "PetController")
    scope.entity = path.basename(scope.id);
    scope.dir = path.dirname(scope.id);
    scope.entity = _.capitalize(scope.entity);
    scope.entity += 'Controller';


    // Determine other default values based on the
    // available scope.
    _.defaults(scope, {
      ext: scope.coffee ? '.coffee' : '.js',
      actions: [],
      destDir: 'api/controllers/'
    });

    _.defaults(scope, {
      rootPath: scope.rootPath,
      filename: path.join(scope.dir, scope.entity + scope.ext),
      lang: scope.coffee ? 'coffee' : 'js'
    });



    //
    // Transforms
    //


    // Render some stringified code from the action template
    // and make it available in our scope for use later on.
    scope.actionFns = scope.actionFns || _.map(scope.actions, function(action) {
      return _.trimRight(
        EMBEDDED_ACTION_TEMPLATE_FN({
          actionName: action,
          lang: scope.coffee ? 'coffee' : 'js',
          commentHeading: util.format('`%s.%s()`', scope.entity, action),
          verbose: scope.verbose,
          IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT: IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT,
        })
      );
    });



    // Trigger callback with no error to proceed.
    return cb();

  },//</before>

};

