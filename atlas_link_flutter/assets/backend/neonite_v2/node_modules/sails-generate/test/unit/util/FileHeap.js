/**
 * Module dependencies
 */

var path = require('path');
var _ = require('@sailshq/lodash');
var fsx = require('fs-extra');


/**
 * Helper to manage/cleanup files created during test runs
 */
module.exports = function FileHeap(options) {
  options = options || {};

  var _aid = 0;
  var _suffix = '.test';
  var _outputPath = path.resolve(options.path || './.tmp/notASailsApp');
  var _files = [];


  this.errors = {
    unknown: function(pathToNewFile) {
      return new Error('Unknown file :: ' + pathToNewFile);
    }
  };

  /**
   * Directory where files are kept
   */
  this.dirpath = _outputPath;



  /**
   * Get new pathToNewFile and reserve it
   *
   * @param {String} [basename] -
   *    -- optional--
   *    This lets you register a particular filename AND
   *    ITS SUFFIX (e.g. `package.json`) with the heap
   *    for automatic garbage-collection.
   */
  this.alloc = function(basename) {

    var pathToNewFile;

    // Take care of optional basename param
    if (basename) {
      pathToNewFile = path.resolve(_outputPath, basename);
      if (fsx.existsSync(pathToNewFile)) {
        fsx.removeSync(pathToNewFile);
        throw new Error('Cannot allocate ' + basename + ':: File already exists.');
      }
      _files.push(pathToNewFile);
      return pathToNewFile;
    }

    // Find a new file, checking if any existing files exist
    // Increase incrementor exponentially to minimize alloc time
    // TODO: optimize if necessary
    var exponentialIterator = 1;
    do {
      _aid += exponentialIterator;
      exponentialIterator *= 2;
      pathToNewFile = path.resolve(_outputPath, _aid + _suffix);
    }
    while (fsx.existsSync(pathToNewFile) || this.contains(pathToNewFile));

    _files.push(pathToNewFile);
    return pathToNewFile;
  };


  /**
   * Write some dummy bytes to a new file with the specified path
   *
   * @param {String} pathToNewFile
   * @param {Function} cb
   */
  this.touch = function(pathToNewFile, cb) {
    if (!this.contains(pathToNewFile)) {
      return cb(this.errors.unknown(pathToNewFile));
    }

    fsx.outputFile(pathToNewFile, 'blah blah', cb);
  };


  /**
   * Write a new JSON file.
   *
   * @param {String} pathToNewFile
   * @param {}
   * @param {Function} cb
   */
  this.outputJSON = function(pathToNewFile, data, cb) {
    if (!this.contains(pathToNewFile)) {
      return cb(this.errors.unknown(pathToNewFile));
    }
    fsx.outputJSON(pathToNewFile, data, cb);
  };


  /**
   * Write a new folder
   *
   * @param {String} pathToNewDir
   * @param {Function} cb
   */
  this.mkdirp = function(pathToNewDir, cb) {
    if (!this.contains(pathToNewDir)) {
      return cb(this.errors.unknown(pathToNewDir));
    }

    fsx.mkdirp(pathToNewDir, cb);
  };



  /**
   * Delete all generated files
   *
   * @param {Function} cb
   */
  this.cleanAll = function(cb) {
    fsx.remove(_outputPath, cb);
  };



  /**
   * @param {String} pathToFile
   * @param {Function} cb
   *    @param {Error} err
   *    @param {String} contents of file
   */
  this.read = function(pathToFile, cb) {
    if (!this.contains(pathToFile)) {
      return cb(this.errors.unknown(pathToFile));
    }
    return fsx.readFile(pathToFile, cb);
  };
  this.readSync = function(pathToFile) {
    if (!this.contains(pathToFile)) {
      throw this.errors.unknown(pathToFile);
    }
    return fsx.readFileSync(pathToFile);
  };


  /**
   * Grab filename from path, with no extension
   */
  this.getFilename = function(pathToFile) {
    if (!this.contains(pathToFile)) {
      throw this.errors.unknown(pathToFile);
    }
    return path.basename(pathToFile, _suffix);
  };



  /**
   * @param {String} pathToNewFile
   * @returns whether the pathToNewFile has been allocated
   */
  this.contains = function(pathToNewFile) {
    return _.contains(_files, pathToNewFile);
  };

};
