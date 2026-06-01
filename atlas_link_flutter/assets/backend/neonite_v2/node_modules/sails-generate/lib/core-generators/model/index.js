/**
 * Module dependencies
 */

var fs = require('fs');
var path = require('path');
var _ = require('@sailshq/lodash');


// On initial require of this file:
//
// • Determine abs path to templates folder.
var TEMPLATES_PATH = path.resolve(__dirname,'./templates');
//
// • Fetch static template string for attr def, and precompile it into a template function.
var ATTR_DEF_TEMPLATE_PATH = path.resolve(TEMPLATES_PATH, './attribute.template');
var ATTR_DEF_TEMPLATE_STR = fs.readFileSync(ATTR_DEF_TEMPLATE_PATH, 'utf8');
var ATTR_DEF_TEMPLATE_FN = _.template(ATTR_DEF_TEMPLATE_STR);



/**
 * sails-generate-model
 *
 * Usage:
 * `sails generate model <resource>`
 *
 * @type {Dictionary}
 */
module.exports = {


  templatesDirectory: TEMPLATES_PATH,


  targets: {

    './api/models/:filename': { template: 'model.template' }

  },


  /**
   * This `before()` function is run before generating targets.
   * It validates user input, configures defaults, gets extra
   * dependencies, etc.
   *
   * @param  {Dictionary} scope
   * @param  {Function} sb    [callback]
   */
  before: function(scope, sb) {

    // Make sure we're in the root of a Sails project.
    var pathToPackageJSON = path.resolve(scope.rootPath, 'package.json');
    var pkgJson;
    try {
      pkgJson = require(pathToPackageJSON);
    } catch (e) {
      // If there is an actual parsing error, display a special message.  If there is no package.json at all,
      // it'll fall through to the "Sorry, this command can only be used in the root directory of a Sails project" error below.
      if (e.code !== 'MODULE_NOT_FOUND') {
        return sb.invalid('Could not parse this directory\'s package.json file.  Could there be a typo... maybe a trailing comma?');
      }
    }

    if (!_.isObject(pkgJson) || !_.isObject(pkgJson.dependencies) || !_.contains(_.keys(pkgJson.dependencies), 'sails')) {
      return sb.invalid('Sorry, this command can only be used in the root directory of a Sails project.');
    }

    // scope.args are the raw command line arguments.
    //
    // e.g. if you run:
    // sails generate controlller user find create update
    // then:
    // scope.args = ['user', 'find', 'create', 'update']
    //
    _.defaults(scope, {
      id: _.capitalize(scope.args[0]),
      attributes: scope.args.slice(1)
    });

    if (!scope.rootPath) {
      return sb.invalid('Usage: sails generate model <modelname> [attribute|attribute:type ...]');
    }
    if (!scope.id) {
      return sb.invalid('Usage: sails generate model <modelname> [attribute|attribute:type ...]');
    }


    // If the model identity seems problematic, warn about it.
    // (For example "String" or good old "Uint8ClampedArray")
    // • https://github.com/balderdashy/sails/issues/3080
    var GRAYLIST = [
      'Array',
      'ArrayBuffer',
      'Boolean',
      'Buffer',
      'DTRACE_HTTP_CLIENT_REQUEST',
      'DTRACE_HTTP_CLIENT_RESPONSE',
      'DTRACE_HTTP_SERVER_REQUEST',
      'DTRACE_HTTP_SERVER_RESPONSE',
      'DTRACE_NET_SERVER_CONNECTION',
      'DTRACE_NET_STREAM_END',
      'DataView',
      'Date',
      'Error',
      'EvalError',
      'Float32Array',
      'Float64Array',
      'Function',
      'GLOBAL',
      'Infinity',
      'Int16Array',
      'Int32Array',
      'Int8Array',
      'Intl',
      'JSON',
      'Map',
      'Math',
      'NaN',
      'Number',
      'Object',
      'Promise',
      'RangeError',
      'ReferenceError',
      'RegExp',
      'Set',
      'String',
      'Symbol',
      'SyntaxError',
      'TypeError',
      'URIError',
      'Uint16Array',
      'Uint32Array',
      'Uint8Array',
      'Uint8ClampedArray',
      'WeakMap',
      'WeakSet'
    ];
    if (_.contains(GRAYLIST, scope.id) || _.contains(GRAYLIST, scope.args[0])) {
      console.warn('*•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•*');
      console.warn('Warning: That model identity might be problematic when/if globals are enabled!');
      console.warn('(Please consider renaming the new file to `the'+scope.args[0]+'.js`');
      console.warn('*•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•*');
    }//>-

    // If the model identity seems spooksome, or altogether nutty, then prevent it entirely.
    var BLACKLIST = [
      '__defineGetter__',
      '__defineSetter__',
      '__lookupGetter__',
      '__lookupSetter__',
      '__proto__',
      'constructor',
      'hasOwnProperty',
      'isPrototypeOf',
      'propertyIsEnumerable',
      'toLocaleString',
      'toString',
      'valueOf',
    ];
    if (_.contains(BLACKLIST, scope.id) || _.contains(BLACKLIST, scope.args[0]) || !scope.args[0].match(/^[a-z]/i)) {
      return sb.invalid('Whoops!  Unfortunately, that model identity conflicts with the name of a core feature of JavaScript or Node.js, so it won\'t do.  Would you try a different model identity?  (e.g. `The'+scope.args[0]+'`)');
    }//-•


    // If the identity potentially won't work because of conflicts in our dependencies, then let the user know.
    //
    // > This last one is only an issue until the changes from this PR get published to NPM:
    // > https://github.com/socketio/has-binary/pull/4
    // > (as well as all of the dependents, including socket.io and then, lastly, sails-hook-sockets)
    var BROWNLIST = [
      'File',
      'Blob'
    ];
    if (_.contains(BROWNLIST, scope.id) || _.contains(BROWNLIST, scope.args[0])) {
      console.warn('*•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•*');
      console.warn('Warning: That model identity might be problematic when/if globals are enabled.');
      console.warn('For example, it can conflict with expectations of 3rd party NPM packages that');
      console.warn('are designed to be usable on both the client and the server (e.g. socket.io).');
      console.warn('(It might be a good idea to delete this model file and instead re-generate');
      console.warn('the model with a different name like `UploadedFile`.)');
      console.warn('*•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•* *•~°~•*');
    }//>-



    // Validate optional attribute arguments
    var attributes = scope.attributes || [];
    var invalidAttributes = [];
    attributes = _.map(attributes, function(attribute) {

      var parts = attribute.split(':');

      if (parts[1] === undefined) {
        parts[1] = 'string';
      }

      // Handle invalidAttributes
      if (!parts[1] || !parts[0]) {
        invalidAttributes.push(
          'Invalid attribute notation:   "' + attribute + '"');
        return;
      }
      return {
        name: parts[0],
        type: parts[1]
      };

    });

    // Handle invalid action arguments
    // Send back invalidActions
    if (invalidAttributes.length) {
      return sb.invalid(invalidAttributes);
    }

    // Make sure there aren't duplicates
    if (_.uniq(_.pluck(attributes, 'name')).length !== attributes.length) {
      return sb.invalid('Duplicate attributes not allowed!');
    }

    //
    // Determine default values based on the
    // available scope.
    //
    _.defaults(scope, {
      globalId: _.capitalize(scope.id),
      ext: (scope.coffee) ? '.coffee' : '.js',
    });

    // Take another pass to take advantage of
    // the defaults absorbed in previous passes.
    _.defaults(scope, {
      filename: scope.globalId + scope.ext,
      lang: scope.coffee ? 'coffee' : 'js',
    });



    //
    // Transforms
    //

    // Render some stringified code from the action template
    var compiledAttrDefs = _.map(attributes, function (attrDef) {
      return _.trimRight(
        ATTR_DEF_TEMPLATE_FN({
          name: attrDef.name,
          type: attrDef.type,
          lang: scope.coffee ? 'coffee' : 'js'
        })
      );
    });

    // Then join it all together and make it available in our scope
    // for use in our targets.
    scope.attributes = compiledAttrDefs.join((scope.coffee) ? '\n' : ',\n');

    // Trigger callback with no error to proceed.
    return sb();

  }//</before>

};

