/**
 * Module dependencies
 */

var util = require('util');
var _ = require('@sailshq/lodash');
var reportback = require('reportback')();

var loadGeneratorDef = require('./load-generator-def');
var generateFolder = require('./builtins/folder');
var generateFileFromTemplate = require('./builtins/template');
var generateJsonFile = require('./builtins/jsonfile');
var generateFileCopy = require('./builtins/copy');


/**
 * Known builtins.
 * @type {Array}
 */
var KNOWN_BUILTINS = ['exec', 'folder', 'template', 'jsonfile', 'file', 'copy'];


/**
 * generateTarget()
 *
 * Generate the specified target using the provided scope.
 * > This module is called from exactly one place: `help-generate.js`
 *
 * @param  {Dictionary}  options
 *     @property {String|Dictionary} target
 *     @property {Dictionary} scope
 *     @property {Dictionary} parentGenerator
 *         @property {String} templatesDirectory
 *     @property {Function} recursiveGenerate
 *               a recursive reference to `helpGenerate()`.
 *
 * @param  {Function}  done
 */

module.exports = function generateTarget(options, done) {

  // Ensure `done` is a reportback, for consistency.
  // (This will likely be removed in a future version Sails.)
  done = reportback.extend(done);

  // Options
  var scope = options.scope;
  var parentGenerator = options.parent;
  var helpGenerateRecursive = options.recursiveGenerate;

  // This local var (`target`) will be used to hold our final, resolved target.
  var target = options.target;

  try {

    // Inherit the `templatesDirectory` from the parent Generator's template directory.
    // (But only if there is one... otherwise just keep whatever's already on the scope.)
    //
    // > Notes:
    // > + This is always an abs path.
    // > + This can still be overridden by this target's definition below.
    // > `scope` is being mutated here!
    if (!_.isUndefined(parentGenerator.templatesDirectory)) {
      scope.templatesDirectory = parentGenerator.templatesDirectory;
    }

    // A special variable we'll use just in case the logic below inside the `while` loop
    // decides it doesn't want us to generate anything at all.
    var dontActuallyGenerateThisOne;

    // Prevent ∞ iterations.
    var MAX_RESOLVES = 5;
    var _resolves = 0;

    while (true) {

      // Try to parse the target.

      // If the target is a string, interpret it as the name of an overridable generator,
      // so expand it into a dictionary accordingly.
      if (_.isString(target)) {
        target = {
          overridable: target,
          generator: target
        };
      }//>-


      // Before moving on, check if this target has a matching `onlyIf`.
      // If so, set a variable so we know not to generate it, then break out of the loop.
      if (target.onlyIf !== undefined) {

        // Check that `onlyIf` syntax is valid.
        if (!_.isString(target.onlyIf)) {
          throw new Error('Unrecognized generator syntax in targets: ' + util.inspect(target, {depth: null}) + '  (If specified, `onlyIf` must be a string: the name of the scope property to check.  If falsey, this target will be skipped.)' );
        }

        if (!scope[target.onlyIf]) {
          dontActuallyGenerateThisOne = true;
          break;
        }//•

      }//ﬁ


      //  ╦  ╔═╗╔═╗╔╦╗  ╔═╗╦  ╦╔═╗╦═╗╦═╗╦╔╦╗╔═╗
      //  ║  ║ ║╠═╣ ║║  ║ ║╚╗╔╝║╣ ╠╦╝╠╦╝║ ║║║╣
      //  ╩═╝╚═╝╩ ╩═╩╝  ╚═╝ ╚╝ ╚═╝╩╚═╩╚═╩═╩╝╚═╝
      //  ┌─    ┬┌─┐  ┌─┐┬  ┬┌─┐┬─┐┬─┐┬┌┬┐┌─┐┌┐ ┬  ┌─┐    ─┐
      //  │───  │├┤   │ │└┐┌┘├┤ ├┬┘├┬┘│ ││├─┤├┴┐│  ├┤   ───│
      //  └─    ┴└    └─┘ └┘ └─┘┴└─┴└─┴─┴┘┴ ┴└─┘┴─┘└─┘    ─┘
      // If this target declares itself overridable, then try to load the package for it.
      // (If we find one, we'll use that instead of whatever was configured.)
      if (target.overridable) {


        // Check that `overridable` syntax is valid.
        if (!_.isString(target.overridable)) {
          throw new Error('Unrecognized generator syntax in targets: ' + util.inspect(target, {depth: null}) + '  (If specified, `overridable` must be a string: the "generator type" to allow this target to be overridden as.)' );
        }

        // Try to require the appropriate generator of this type.
        try {

          // If it works, point `target.generator` straight at the generator def.
          target = {
            generator: loadGeneratorDef({
              generatorType: target.overridable,
              topLvlRootPath: scope.topLvlRootPath,
              modules: scope.modules
            })
          };

        } catch (e) {
          switch (e.code) {

            // If it could not be loaded, that's ok.
            // (We'll still continue below anyway and just use whatever we have in the target otherwise.)
            case 'generatorNotFound':
              break;

            // If an unexpected fatal error occurred, handle it.
            default:
              throw e;

          }
        }//</catch>

      }//</if :: target.overridable>
      //>-•
      //
      // At this point, if this target could be overridden and we were able
      // to load an override, then we've done so already (and updated our target
      // accordingly.)  And if not, then we haven't.

      // Aside:
      // The word "overridable" is kind of hard to spell.
      // So just in case we see any other likely spelling, trigger
      // a fatal error.
      //
      // > Note that this could eventually be changed over to be a generic
      // > "unrecognized property" check.  But for now, just cutting to the
      // > chase and solving the thing that ate like an hour of my time.
      if (!_.isUndefined(target.overidable) || !_.isUndefined(target.overriddable) || !_.isUndefined(target.overiddable) || !_.isUndefined(target.overideable) || !_.isUndefined(target.overrideable) || !_.isUndefined(target.overiddeable)) {
        throw new Error('Unrecognized target syntax: Please check your spelling.  Did you mean "overridable"?');
      }


      // Now check if this target is valid.

      // If target is pointed at a builtin, then bail now.
      // (we can use the target exactly as-is)
      var isTargetPointedAtBuiltin = _.isObject(target) && _.intersection(_.keys(target), KNOWN_BUILTINS).length > 0;
      if (isTargetPointedAtBuiltin) {
        break;
      }//-•

      var isTargetAGeneratorPrbly = _.isObject(target) && _.isObject(target.generator);
      if (isTargetAGeneratorPrbly) {
        // IWMIH, then we can assume that this target is referencing a generator (or at least trying to).
        // That means we can expect `target.generator` to be present, and to be a valid inline generator
        // definition.

        // Verify that the `generator` of our target is now a dictionary, like it should be.
        if (!_.isPlainObject(target.generator)) {
          throw new Error('Generator error: Invalid sub-generator configuration for target "' + scope.rootPath + '": '+util.inspect(target.generator, {depth:null}));
        }

        // Otherwise, the target's `generator` is a dictionary, so we'll treat it as an inline
        // sub-generator definition and finish up.
        target = target.generator;
        break;

      }//-•

      // But if it's not, then increment the counter.
      // (And check if we've reached MAX_RESOLVES-- if so, then we'll throw and stop.)
      _resolves++;
      if (_resolves > MAX_RESOLVES) {
        throw new Error('Generator error: Could not resolve target "' + scope.rootPath + '" due to a recursive loop.  (Exceeded maximum of '+MAX_RESOLVES+' tries.)');
      }//-•

    }//∞  </while>

    // If we decided to straight-up cancel this target, do that now.
    if (dontActuallyGenerateThisOne) {
      return done();
    }//•

    // Now interpret generator definition:
    // (note that `scope` is being mutated along the way!)

    //  ╔═╗═╗ ╦╔═╗╔═╗
    //  ║╣ ╔╩╦╝║╣ ║
    //  ╚═╝╩ ╚═╚═╝╚═╝
    if (_.isFunction(target.exec)) {
      target.exec(scope, done);
      return;
    }//-•

    if (!_.isUndefined(target.exec)){ throw new Error('Invalid target syntax: `exec` must be specified as a function.'); }


    //  ╔═╗╔═╗╔═╗╦ ╦
    //  ║  ║ ║╠═╝╚╦╝
    //  ╚═╝╚═╝╩   ╩
    if (_.isString(target.copy)) {
      _.extend(scope, { templatePath: target.copy });
      generateFileCopy(scope, done);
      return;
    }//-•

    if (_.isPlainObject(target.copy)) {
      _.merge(scope, target.copy);
      generateFileCopy(scope, done);
      return;
    }//-•

    if (!_.isUndefined(target.copy)) { throw new Error('Invalid target syntax: `copy` must be specified as a dictionary or a string.'); }//-•


    //  ╔═╗╔═╗╦  ╔╦╗╔═╗╦═╗
    //  ╠╣ ║ ║║   ║║║╣ ╠╦╝
    //  ╚  ╚═╝╩═╝═╩╝╚═╝╩╚═
    if (target.folder) {
      _.merge(scope, target.folder);
      generateFolder(scope, done);
      return;
    }//-•

    if (!_.isUndefined(target.folder)) { throw new Error('Invalid target syntax: `folder` must be specified as a dictionary.'); }//-•


    //  ╔╦╗╔═╗╔╦╗╔═╗╦  ╔═╗╔╦╗╔═╗
    //   ║ ║╣ ║║║╠═╝║  ╠═╣ ║ ║╣
    //   ╩ ╚═╝╩ ╩╩  ╩═╝╩ ╩ ╩ ╚═╝
    if (_.isString(target.template)) {
      _.extend(scope, { templatePath: target.template });
      generateFileFromTemplate(scope, done);
      return;
    }//-•

    if (_.isPlainObject(target.template)) {
      _.merge(scope, target.template);
      generateFileFromTemplate(scope, done);
      return;
    }//-•

    if (!_.isUndefined(target.template)) { throw new Error('Invalid target syntax: `template` must be specified as a dictionary or a string.'); }//-•


    //   ╦╔═╗╔═╗╔╗╔╔═╗╦╦  ╔═╗
    //   ║╚═╗║ ║║║║╠╣ ║║  ║╣
    //  ╚╝╚═╝╚═╝╝╚╝╚  ╩╩═╝╚═╝
    if (_.isFunction(target.jsonfile)) {
      var jsonDataToUse = target.jsonfile(scope);
      _.extend(scope, { data: jsonDataToUse });
      generateJsonFile(scope, done);
      return;
    }//-•

    if (_.isPlainObject(target.jsonfile)) {
      _.merge(scope, target.jsonfile);
      generateJsonFile(scope, done);
      return;
    }//-•

    if (!_.isUndefined(target.jsonfile)) { throw new Error('Invalid target syntax: `jsonfile` must be specified as a dictionary or a function.'); }//-•


    //  ╔═╗╔═╗╔╦╗╔═╗  ╔═╗╔╦╗╦ ╦╔═╗╦═╗  ╔═╗╔═╗╔╗╔╔═╗╦═╗╔═╗╔╦╗╔═╗╦═╗
    //  ╚═╗║ ║║║║║╣   ║ ║ ║ ╠═╣║╣ ╠╦╝  ║ ╦║╣ ║║║║╣ ╠╦╝╠═╣ ║ ║ ║╠╦╝
    //  ╚═╝╚═╝╩ ╩╚═╝  ╚═╝ ╩ ╩ ╩╚═╝╩╚═  ╚═╝╚═╝╝╚╝╚═╝╩╚═╩ ╩ ╩ ╚═╝╩╚═
    // If we made it here, this must be a recursive generator.
    // So real quick, check to make sure maxHops has not been exceeded.
    if (++scope._depth > scope.maxHops) {
      throw new Error('`maxHops` (' + scope.maxHops + ' exceeded!  There is probably a recursive loop in one of your generators.');
    }//-•

  } catch (e) { return done(e); }

  // And now that the generator target has been resolved,
  // call this method recursively on it, passing along our
  // callback:
  helpGenerateRecursive(target, scope, function (err) {
    if (err) { return done(err); }
    return done();
  });


};

