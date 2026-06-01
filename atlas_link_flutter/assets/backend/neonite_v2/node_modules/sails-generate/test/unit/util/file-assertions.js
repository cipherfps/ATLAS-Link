/**
 * Module depencencies
 */

var checksum = require('checksum');
var fsx = require('fs-extra');



module.exports = {

  //
  // TODO: use lstat instead of readdir and readFile
  // for these existence checks.
  // (low priority- just makes tests run faster)
  //



  /**
   * @param {Function} cb
   *
   * @this {Dictionary} options
   */
  fileExists: function(cb) {
    fsx.readFile(this.options.rootPath, cb);
  },

  /**
   * @param {Function} cb
   *
   * @this {Dictionary} options
   */
  fileDoesntExist: function(cb) {
    fsx.readFile(this.options.rootPath, function(err) {
      if (err && err.code === 'ENOENT') {
        return cb();
      } else if (err) { return cb(err); }
      else { return cb(new Error('File should not exist.')); }
    });
  },



  /**
   * @param {Function} cb
   *
   * @this {Dictionary} options
   */
  dirExists: function(cb) {
    fsx.readdir(this.options.rootPath, cb);
  },


  /**
   * @param {Function} cb
   *
   * @this {Dictionary} options
   */
  dirDoesntExist: function(cb) {
    fsx.readdir(this.options.rootPath, function(err) {
      if (err && err.code === 'ENOENT') {
        return cb();
      } else if (err) { return cb(err); }
      else {return cb(new Error('Directory should not exist.'));}
    });
  },



  /**
   * @param {Function} cb
   *
   * @this {Dictionary} options
   */
  fileIsExactly: function(compareStr) {
    return function(cb) {
      fsx.readFile(this.options.rootPath, function(err, contents) {
        if (err) { return cb(err); }
        return cb(null, checksum(compareStr) === checksum(contents));
      });
    };
  },



  /**
   * @param {Function} cb
   *
   * @this {Dictionary} options
   */
  fileIsNot: function(compareStr) {
    return function(cb) {
      fsx.readFile(this.options.rootPath, function(err, contents) {
        if (err) { return cb(err); }
        return cb(null, checksum(compareStr) !== checksum(contents));
      });
    };
  },



  /**
   * @param {Function} cb
   *
   * @this {Dictionary} templates
   * @this {Dictionary} options
   */
  fileChecksumMatchesTemplate: function(cb) {
    var templateChecksum = this.templates.file.checksum;
    fsx.readFile(this.options.rootPath, function(err, contents) {
      if (err) { return cb(err); }
      return cb(null, templateChecksum === checksum(contents));
    });
  }
};
