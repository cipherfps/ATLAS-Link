/**
 * Module dependencies
 */

var path = require('path');
var _ = require('@sailshq/lodash');


/**
 * Usage:
 * `sails generate email foo`
 *
 * Or:
 * `sails generate email internal/foo`
 */

module.exports = {

  templatesDirectory: path.resolve(__dirname,'./templates'),

  /**
   * Scope:
   * ----------------------------------------------------
   * @option {Array} args   [command-line arguments]
   * ----------------------------------------------------
   * @property {String} relPath
   * @property {String} stem
   *
   * @property {String} newEmailRelPath
   */

  before: function (scope, exits) {
    if (!scope.args[0]) {
      return exits.error(
        'Please specify the base name or path for the new email.\n'+
        '(relative from the `views/emails/` folder;\n'+
        ' e.g. `email-recover-password`-- or `recover-password` for short)'
      );
    }

    // e.g. `email-recover-password`
    scope.relPath = scope.args[0];

    // Check if it has a file extension and, if so, reject it.
    if (path.extname(scope.relPath)) {
      return exits.error('Please specify the base name or path for the new email, excluding the filename suffix (i.e. no ".ejs")');
    }

    // Trim any whitespace from both sides.
    scope.relPath = _.trim(scope.relPath);

    // Check that it does not have any trailing slashes.
    if (scope.relPath.match(/\/$/)) {
      return exits.error('Please specify the base name or path for the new email. (No trailing slash please.)');
    }

    // Check that it does not begin with a slash or a dot dot slash.
    // (a single dot+slash is ok, since you might be using tab-completion in the terminal)
    if (scope.relPath.match(/^\.\.+\//) || scope.relPath.match(/^\//)) {
      return exits.error('No need for dots and leading slashes and things. Please specify something like: `email-recover-password` or `internal/email-contact-form`');
    }

    // Make sure the relative path is not within "emails/", "views/", "controllers/",
    // "assets/", "js/", "styles/", or anything else like that.  If it is, it's probably
    // an accident.  And if it's not an accident, it's still super confusing.
    if (scope.relPath.match(/^(emails\/|pages\/|views\/|controllers\/|api\/|assets\/|js\/|styles\/)/i)) {
      return exits.error('Please specify *just* the relative path for the new email, excluding prefixes like "emails/" or "views/".  Those will be attached for you automatically-- you just need to include the last bit; e.g. `email-recover-password` or  `internal/email-recover-password`');
    }

    // Gracefully ignore double-slashes.
    scope.relPath = scope.relPath.replace(/\/\/+/, '/');

    // Gracefully ignore leading "./", if present.
    scope.relPath = scope.relPath.replace(/^[\.\/]+/, '');

    // Make sure all parent sub-folders are kebab-cased and don't contain any
    // uppercase or non-alphanumeric characters (except dashes are ok, of course).
    var parentSubFoldersString = path.dirname(scope.relPath);
    var arrayOfParentSubFolders = parentSubFoldersString==='.' ? [] : parentSubFoldersString.split(/\//);
    try {
      _.each(arrayOfParentSubFolders, function(subFolderName){
        if (subFolderName !== _.kebabCase(subFolderName)) {
          throw new Error('Please make sure any parent sub-folders are written in kebab-case; e.g. "internal/business-process/foobar", and NOT "internalStuff/business_process/dontDoTHIS/please"');
        }
        if (subFolderName.match(/[^a-z0-9\-]/) || subFolderName !== _.deburr(subFolderName)){
          throw new Error('Please stick to alphanumeric characters and dashes.');
        }
      });//∞
    } catch (err) { return exits.error(err.message); }

    // Tease out the "stem".
    // (e.g. `email-recover-password`)
    var originalStem = path.basename(scope.relPath);

    // Then kebab-case it, if it isn't already.
    // (e.g. `emailRecoverPassword` becomes `email-recover-password`)
    var newStem = _.kebabCase(originalStem);

    // Check if it starts with `email-`, and if so, lop that off.
    // (e.g. `email-recover-password` or `internal/email-contact-form`)
    if (newStem.match(/^email-/)) {
      newStem = newStem.replace(/^email-/, '');
    }

    // Then attach `email-`.
    newStem = 'email-'+newStem;

    // Check that the stem doesn't still contain any uppercase or non-alphanumeric
    // characters.  (Except dashes are ok, of course.)
    if (newStem.match(/[^a-z0-9\-]/) || newStem !== _.deburr(newStem)) {
      return exits.error('Please stick to alphanumeric characters and dashes.');
    }

    // If the stem has changed, update the relPath.
    if (newStem !== originalStem) {
      scope.relPath = scope.relPath.replace(new RegExp(_.escapeRegExp(originalStem)), newStem);
    }

    // ◊  (Now then…)
    scope.stem = newStem;
    scope.newEmailRelPath = path.join('views/emails/', scope.relPath+'.ejs');

    // Disable the "Created a new …!" output so we can use our own instead.
    scope.suppressFinalLog = true;

    return exits.success();
  },

  after: function (scope, done){
    console.log();
    console.log('Successfully generated:');
    console.log(' •-',scope.newEmailRelPath);
    console.log();
    console.log('Remember:');
    console.log(' (•)  This file was generated assuming your Sails app is using');
    console.log('      an email layout.  (If you\'re unsure, head over to the');
    console.log('      resources at https://sailsjs.com/support)');
    console.log();
    return done();
  },

  targets: {
    './:newEmailRelPath': { copy: 'email.ejs' },
  }

};
