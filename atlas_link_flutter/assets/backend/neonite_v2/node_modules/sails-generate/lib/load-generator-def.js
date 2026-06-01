/**
 * Module dependencies
 */

var util = require('util');
var path = require('path');
var _ = require('@sailshq/lodash');
var flaverr = require('flaverr');


/**
 * loadGeneratorDef()
 *
 * Attempt to require the specified generator.
 *
 * @required {String} generatorType
 * @required {String} topLvlRootPath
 * @optional {Dictionary} modules
 *
 * @returns {Dictionary}
 *          generator definition
 *
 * @throws {Error} If no matching generator could be found
 *         @property {String} code   (=== 'generatorNotFound')
 */

module.exports = function loadGeneratorDef(options) {

  // Sanity checks:
  if (!options.generatorType) { throw new Error('Consistency violation: Sorry, `options.generatorType` must be defined and truthy.'); }
  if (!_.isString(options.generatorType)) { throw new Error('Consistency violation: Sorry, `options.generatorType` must be a string.'); }
  if (!_.isUndefined(options.modules)) {
    if (!_.isObject(options.modules) || _.isArray(options.modules) || _.isFunction(options.modules)) {
      throw new Error('Consistency violation: Invalid `options.modules`:  Should be a dictionary, but instead got: '+util.inspect(options.modules, {depth: null}));
    }
  }

  // Use configured package name / module path in `modules[generatorType]` if one exists.
  var generatorModulePathOrPkgName;
  if (options.modules && !_.isUndefined(options.modules[options.generatorType])) {


    // If configured as `false`, then just return a no-op target which uses the `exec` builtin.
    if (options.modules[options.generatorType] === false) {
      return { exec: function noop(scope, done) { return done(); } };
    }//-•

    // If configured as a dictionary, and if it has `targets`, then assume this is an inline generator definition.
    if (_.isObject(options.modules[options.generatorType]) && !_.isArray(options.modules[options.generatorType]) && !_.isFunction(options.modules[options.generatorType])) {
      return options.modules[options.generatorType];
    }//-•

    if (!_.isString(options.modules[options.generatorType])) {
      throw new Error('Invalid package name/module path configured as `modules[\''+options.generatorType+'\']` (check your .sailsrc or programmatic config).  Should be either (A) a string (package name or path to generator) (B) false, or (C) an inline generator def, but instead got: '+util.inspect(options.modules[options.generatorType], {depth: null}));
    }//-•

    generatorModulePathOrPkgName = options.modules[options.generatorType];

  }//>-•

  // Determine if the configured package name / module path looks like an abs path, a rel path, or neither.
  var looksLikeRelPath;
  var looksLikeAbsPath;
  if (generatorModulePathOrPkgName) {
    looksLikeRelPath = _.startsWith(generatorModulePathOrPkgName, '.');
    looksLikeAbsPath = path.isAbsolute(generatorModulePathOrPkgName);
  }


  //  ██████╗ ███████╗████████╗███████╗██████╗ ███╗   ███╗██╗███╗   ██╗███████╗
  //  ██╔══██╗██╔════╝╚══██╔══╝██╔════╝██╔══██╗████╗ ████║██║████╗  ██║██╔════╝
  //  ██║  ██║█████╗     ██║   █████╗  ██████╔╝██╔████╔██║██║██╔██╗ ██║█████╗
  //  ██║  ██║██╔══╝     ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║██║██║╚██╗██║██╔══╝
  //  ██████╔╝███████╗   ██║   ███████╗██║  ██║██║ ╚═╝ ██║██║██║ ╚████║███████╗
  //  ╚═════╝ ╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚══════╝
  //
  //  ██████╗ ███████╗ ██████╗ ██╗   ██╗██╗██████╗ ███████╗███████╗    ████████╗ ██████╗
  //  ██╔══██╗██╔════╝██╔═══██╗██║   ██║██║██╔══██╗██╔════╝██╔════╝    ╚══██╔══╝██╔═══██╗
  //  ██████╔╝█████╗  ██║   ██║██║   ██║██║██████╔╝█████╗  ███████╗       ██║   ██║   ██║
  //  ██╔══██╗██╔══╝  ██║▄▄ ██║██║   ██║██║██╔══██╗██╔══╝  ╚════██║       ██║   ██║   ██║
  //  ██║  ██║███████╗╚██████╔╝╚██████╔╝██║██║  ██║███████╗███████║       ██║   ╚██████╔╝
  //  ╚═╝  ╚═╝╚══════╝ ╚══▀▀═╝  ╚═════╝ ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝       ╚═╝    ╚═════╝
  //
  //   █████╗ ████████╗████████╗███████╗███╗   ███╗██████╗ ████████╗
  //  ██╔══██╗╚══██╔══╝╚══██╔══╝██╔════╝████╗ ████║██╔══██╗╚══██╔══╝
  //  ███████║   ██║      ██║   █████╗  ██╔████╔██║██████╔╝   ██║
  //  ██╔══██║   ██║      ██║   ██╔══╝  ██║╚██╔╝██║██╔═══╝    ██║
  //  ██║  ██║   ██║      ██║   ███████╗██║ ╚═╝ ██║██║        ██║
  //  ╚═╝  ╚═╝   ╚═╝      ╚═╝   ╚══════╝╚═╝     ╚═╝╚═╝        ╚═╝
  //
  // Attempt to require the generator definition in the following ways:
  // > (in descending order of priority)
  var requiresToAttempt = [];

  //  ┬┌─┐  ╔═╗═╗ ╦╔═╗╦  ╦╔═╗╦╔╦╗  ┌┬┐┌─┐┌┬┐┬ ┬┬  ┌─┐  ┌─┐┌─┐┌┬┐┬ ┬
  //  │├┤   ║╣ ╔╩╦╝╠═╝║  ║║  ║ ║   ││││ │ │││ ││  ├┤   ├─┘├─┤ │ ├─┤
  //  ┴└    ╚═╝╩ ╚═╩  ╩═╝╩╚═╝╩ ╩   ┴ ┴└─┘─┴┘└─┘┴─┘└─┘  ┴  ┴ ┴ ┴ ┴ ┴
  //  ┌─┐┬─┐  ┌─┐┌─┐┌─┐┬┌─┌─┐┌─┐┌─┐  ┌┐┌┌─┐┌┬┐┌─┐
  //  │ │├┬┘  ├─┘├─┤│  ├┴┐├─┤│ ┬├┤   │││├─┤│││├┤
  //  └─┘┴└─  ┴  ┴ ┴└─┘┴ ┴┴ ┴└─┘└─┘  ┘└┘┴ ┴┴ ┴└─┘ooo
  // If an explicit generator package name / module path was specified, add some additional requires.
  if (generatorModulePathOrPkgName) {

    if (looksLikeAbsPath) {

      // `<<generatorModulePathOrPkgName>>`
      // > i.e. `require()` as absolute path
      requiresToAttempt.push(
        generatorModulePathOrPkgName
      );

    }
    else if (looksLikeRelPath) {

      // `<<topLvlRootPath>>/<<generatorModulePathOrPkgName>>`
      // > i.e. `require()` as relative path
      requiresToAttempt.push(
        path.resolve(options.topLvlRootPath, generatorModulePathOrPkgName)
      );

    }
    // Otherwise, attempt to require as package name:
    else {

      // `<<topLvlRootPath>>/node_modules/<<generatorModulePathOrPkgName>>`
      requiresToAttempt.push(
        path.resolve(options.topLvlRootPath, 'node_modules', generatorModulePathOrPkgName)
      );

      // `<<generatorModulePathOrPkgName>>`
      // > i.e. a normal `require()` -- from any global deps installed in `${HOME}` (and technically
      // > also from sails-generate's own dependencies, though that _should_ never actually be relevant
      // > nowadays, unless something really weird is going on)
      requiresToAttempt.push(
        generatorModulePathOrPkgName
      );

    }//</else :: does not look like relative path>

  }//</if :: explicit generator module path or pkg name was specified>
  //  ╔═╗╦  ╔═╗╔═╗
  //  ║╣ ║  ╚═╗║╣
  //  ╚═╝╩═╝╚═╝╚═╝ooo
  //  ┌─    ┬┌┐┌┌─┐┌─┐┬─┐  ┌─┐┬┌─┌─┐┌┐┌┌─┐┌┬┐┌─┐   ┬   ┌┬┐┬─┐┬ ┬  ┌─┐┌─┐┬─┐┌─┐  ┌─┐┌┐┌┬─┐┌─┐    ─┐
  //  │───  ││││├┤ ├┤ ├┬┘  ├─┘├┴┐│ ┬│││├─┤│││├┤   ┌┼─   │ ├┬┘└┬┘  │  │ │├┬┘├┤   │ ┬│││├┬┘└─┐  ───│
  //  └─    ┴┘└┘└  └─┘┴└─  ┴  ┴ ┴└─┘┘└┘┴ ┴┴ ┴└─┘  └┘    ┴ ┴└─ ┴   └─┘└─┘┴└─└─┘  └─┘┘└┘┴└─└─┘    ─┘
  // Otherwise NO generator package name / module path was provided, so try a few other things.
  else {

    // First, try resolving this as a core generator (`core-generators/` in THIS PACKAGE)
    requiresToAttempt.push(
      path.resolve(__dirname, './core-generators', options.generatorType)
    );

    // ====================================================================================================
    // <FOR BACKWARDS COMPAT>
    // ====================================================================================================
    // 0.98.
    // Attempt to require as an absolute path resolved from:
    // `<<topLvlRootPath>>/node_modules/sails-generate-<<generatorType>>`
    requiresToAttempt.push(
      path.resolve(options.topLvlRootPath, 'node_modules', 'sails-generate-'+options.generatorType)
    );
    //
    // 0.99.
    // Attempt to require as package name derived from generator type (sails-generate- prefix)--
    // i.e. a normal `require()` -- from any global deps installed in `${HOME}` (and technically
    // also from sails-generate's own dependencies, though that _should_ never actually be relevant
    // nowadays, unless something really weird is going on)
    requiresToAttempt.push(
      'sails-generate-'+options.generatorType
    );
    // ====================================================================================================
    // </FOR BACKWARDS COMPAT>
    // ====================================================================================================

  }//</else>
  //>-



  //  ██████╗ ███████╗███████╗ ██████╗ ██████╗ ███╗   ███╗
  //  ██╔══██╗██╔════╝██╔════╝██╔═══██╗██╔══██╗████╗ ████║
  //  ██████╔╝█████╗  █████╗  ██║   ██║██████╔╝██╔████╔██║
  //  ██╔═══╝ ██╔══╝  ██╔══╝  ██║   ██║██╔══██╗██║╚██╔╝██║
  //  ██║     ███████╗██║     ╚██████╔╝██║  ██║██║ ╚═╝ ██║
  //  ╚═╝     ╚══════╝╚═╝      ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝
  //
  //  ██████╗ ███████╗ ██████╗ ██╗   ██╗██╗██████╗ ███████╗
  //  ██╔══██╗██╔════╝██╔═══██╗██║   ██║██║██╔══██╗██╔════╝
  //  ██████╔╝█████╗  ██║   ██║██║   ██║██║██████╔╝█████╗
  //  ██╔══██╗██╔══╝  ██║▄▄ ██║██║   ██║██║██╔══██╗██╔══╝
  //  ██║  ██║███████╗╚██████╔╝╚██████╔╝██║██║  ██║███████╗
  //  ╚═╝  ╚═╝╚══════╝ ╚══▀▀═╝  ╚═════╝ ╚═╝╚═╝  ╚═╝╚══════╝
  //
  //   █████╗ ████████╗████████╗███████╗███╗   ███╗██████╗ ████████╗███████╗
  //  ██╔══██╗╚══██╔══╝╚══██╔══╝██╔════╝████╗ ████║██╔══██╗╚══██╔══╝██╔════╝
  //  ███████║   ██║      ██║   █████╗  ██╔████╔██║██████╔╝   ██║   ███████╗
  //  ██╔══██║   ██║      ██║   ██╔══╝  ██║╚██╔╝██║██╔═══╝    ██║   ╚════██║
  //  ██║  ██║   ██║      ██║   ███████╗██║ ╚═╝ ██║██║        ██║   ███████║
  //  ╚═╝  ╚═╝   ╚═╝      ╚═╝   ╚══════╝╚═╝     ╚═╝╚═╝        ╚═╝   ╚══════╝
  //
  // A local variable to hold the generator definition that we're trying to load
  // in a few different ways below.
  var generatorDef;

  // This outer try/catch is here to handle unexpected require errors along the way.
  try {

    // Attempt each require, in order, until either:
    // A) it is successful
    // B) we run into an unexpected error, or
    // C) we run out of things to try
    //
    // > Note that we only use `_.any()` so that we can break out of the loop.
    _.any(requiresToAttempt, function (requireToAttempt){

      try {
        generatorDef = require(requireToAttempt);

        // If we made it here, we must have found it and been able to successfully require it.

        // Check that it is valid (and if not, throw an error to jump to our `catch` below)
        if (!_.isPlainObject(generatorDef)) {
          throw new Error('Invalid generator definition: Should be a dictionary, but instead got: '+util.inspect(generatorDef, {depth: null}));
        }

        // console.log('For generator `'+options.generatorType+'`, using package:',requireToAttempt);

        // Otherwise, it's probably good to go!
        // So now we can return `true`, which will result in us breaking out of this loop.
        return true;
      }
      catch (e) {

        var CONTAINS_GENERATOR_MODULE_PATH_RX = new RegExp(_.escapeRegExp(requireToAttempt));
        var isRelevantModuleNotFoundError = (
          e.code === 'MODULE_NOT_FOUND' &&
          e.message.match(CONTAINS_GENERATOR_MODULE_PATH_RX)
        );

        // If this is a relevant MODULE_NOT_FOUND error, then we'll ignore it
        // and keep trying (i.e. continuing to the next iteration of our loop).
        if (isRelevantModuleNotFoundError) {
          return;
        }//-•

        // Otherwise, this is some misc. unrecognized error-- so in that case, we'll attach an
        // `attemptedRequire` prop for convenience, then throw again to jump to the outer `catch` below.
        e.attemptedRequire = requireToAttempt;
        throw e;

      }//</catch : MODULE_NOT_FOUND error>

    });//</_.any>

  }//</try :: require generator from somewhere maybe>
  catch (e) {

    // Handle unexpected error by logging, then bailing with a fatal error.
    var unexpectedRequireErrMsg = (function _buildErrorMsg(){

      var appropriatePreposition;
      if (e.attemptedRequire && path.isAbsolute(e.attemptedRequire)) {
        appropriatePreposition = 'from';
      }
      else {
        appropriatePreposition = 'as';
      }

      return 'Encountered unexpected error when loading "'+options.generatorType+'" generator '+appropriatePreposition + ' `'+e.attemptedRequire+'`.';
    })();//</self-calling convenience function :: build error msg>
    throw new Error(unexpectedRequireErrMsg+'\nDetails: '+e.stack);

  }//</catch>-•

  // If we could not locate a generator of this type, then log a message and bail.
  if (!generatorDef) {

    // If this was a specifically configured generator, use a more specific error message.
    // > (Otherwise just use the generic error message.)
    var gnfErrorMsg;
    if (generatorModulePathOrPkgName) {

      if (looksLikeAbsPath) {
        gnfErrorMsg = 'No "' + options.generatorType + '" generator found.'+'\n';
        gnfErrorMsg += 'Could not require a generator definition from the configured module path:'+'\n';
        gnfErrorMsg += '`'+generatorModulePathOrPkgName+'`'+'\n';
        gnfErrorMsg += 'Does that look right?  If not, please fix it in your .sailsrc file.'+'\n';
        gnfErrorMsg += '(If the path DOES look correct, check that a valid generator exists there.)';
      }
      else if (looksLikeRelPath) {
        gnfErrorMsg = 'No "' + options.generatorType + '" generator found.'+'\n';
        gnfErrorMsg += 'Could not require a generator definition at the configured relative module path:'+'\n';
        gnfErrorMsg += '`'+generatorModulePathOrPkgName+'`'+'\n';
        gnfErrorMsg += '\n';
        gnfErrorMsg += 'Does that look right?  If not, please fix it in your .sailsrc file.'+'\n';
        gnfErrorMsg += '(In this case, the relative path was resolved from `'+options.topLvlRootPath+'`.)';
      }
      else {
        gnfErrorMsg = 'No "' + options.generatorType + '" generator found.'+'\n';
        gnfErrorMsg += 'The configured package name (`'+generatorModulePathOrPkgName+'`) does not match any installed generator.'+'\n';
        gnfErrorMsg += 'This probably just means you need to install it (or that your `.sailsrc` file has a typo.)'+'\n';
        gnfErrorMsg += 'Would you try running `npm install '+generatorModulePathOrPkgName+'`?';
      }

    }//</if generatorModulePathOrPkgName>
    else {

      gnfErrorMsg = 'No generator called `' + options.generatorType + '` found.'+'\n';
      gnfErrorMsg += 'Did you mean `sails generate api ' + options.generatorType + '`?\n';
      gnfErrorMsg += '\n';
      gnfErrorMsg += 'Tip: Want to use a custom or community generator?'+'\n';
      gnfErrorMsg += 'Add it to your app\'s .sailsrc file under `modules`:'+'\n';
      gnfErrorMsg += 'You can use a relative path:' + '\n';
      gnfErrorMsg += '```'+'\n';
      gnfErrorMsg += '"modules": {'+'\n';
      gnfErrorMsg += '  "'+options.generatorType+'": "./generators/'+options.generatorType+'"'+'\n';
      gnfErrorMsg += '}' + '\n';
      gnfErrorMsg += '```'+'\n';
      // gnfErrorMsg += '\n';
      gnfErrorMsg += 'Or the name of an NPM package:' + '\n';
      gnfErrorMsg += '```'+'\n';
      gnfErrorMsg += '"modules": {'+'\n';
      gnfErrorMsg += '  "'+options.generatorType+'": "sails-generate-react-component"'+'\n';
      gnfErrorMsg += '}' + '\n';
      gnfErrorMsg += '```';

    }//</else>

    // Add suffix
    gnfErrorMsg += '\n';
    gnfErrorMsg += 'For help, see:'+'\n';
    gnfErrorMsg += 'https://sailsjs.com/docs/concepts/extending-sails/generators';

    // Throw the error.
    throw flaverr('generatorNotFound', new Error(gnfErrorMsg));

  }//-•

  // Return the generator definition.
  return generatorDef;

};
