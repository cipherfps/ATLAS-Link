/**
 * Module dependencies
 */

var expect = require('./util/expect-handler');
var assert = require('./util/file-assertions');
var runBeforeAndAfter = require('./util/run-before-and-after');

var builtinGenerateFolder = require('../../lib/builtins/folder');



describe('folder generator', function() {

  // Set up generic before+after test lifecycle.
  runBeforeAndAfter();

  before(function() {
    this.fn = builtinGenerateFolder;
    this.options = {};
  });



  describe('with missing `rootPath`', function() {
    it('should trigger `invalid`', expect('invalid'));
  });



  describe('basic usage', function() {

    before(function() {
      this.options = {
        rootPath: this.heap.alloc()
      };
    });

    it('should trigger `success`', expect({
      success: true,
      alreadyExists: 'Folder already exists..?'
    }));
    it('should create a directory', assert.dirExists);

  });


  describe('with dry run enabled', function() {
    before(function() {
      this.options = {
        rootPath: this.heap.alloc(),
        contents: 'foo',
        dry: true
      };
    });

    it('should trigger `success`', expect('success'));
    it('should not actually create a directory', assert.dirDoesntExist);
  });


  describe('if file/folder already exists at `rootPath`', function() {
    before(function() {
      this.options = {};
    });

    describe('(file)', function() {
      // Create an extra file beforehand to simulate a collision
      before(function(cb) {
        this.options.rootPath = this.heap.alloc();
        this.heap.touch(this.options.rootPath, cb);
      });
      it('should trigger "alreadyExists" handler', expect({
        alreadyExists: true,
        success: 'Should not override existing file/directory without `options.force`!'
      }));
    });

    describe('(directory)', function() {
      // Create an extra folder beforehand to simulate a collision
      before(function(cb) {
        this.options.rootPath = this.heap.alloc();
        this.heap.mkdirp(this.options.rootPath, cb);
      });
      it('should trigger "alreadyExists" handler', expect({
        alreadyExists: true,
        success: 'Should not override existing file/directory without `options.force`!'
      }));
    });

  });


  describe('if file/folder already exists and `force` option is true', function() {
    before(function() {
      this.options = {
        force: true
      };
    });

    describe('(file)', function() {
      before(function(cb) {
        this.options.rootPath = this.heap.alloc();

        // Create an extra file beforehand to simulate a collision
        this.heap.touch(this.options.rootPath, cb);
      });

      it('should trigger `success`', expect('success'));
    });

    describe('(directory)', function() {
      before(function(cb) {
        this.options.rootPath = this.heap.alloc();

        // Create an extra dir beforehand to simulate a collision
        this.heap.mkdirp(this.options.rootPath, cb);
      });

      it('should trigger `success`', expect('success'));
    });

  });


});
