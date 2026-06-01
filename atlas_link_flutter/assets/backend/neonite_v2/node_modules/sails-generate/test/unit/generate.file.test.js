/**
 * Module dependencies
 */

var expect = require('./util/expect-handler');
var assert = require('./util/file-assertions');
var runBeforeAndAfter = require('./util/run-before-and-after');

var builtinGenerateFile = require('../../lib/builtins/file');


describe('file generator', function() {

  // Set up generic before+after test lifecycle.
  runBeforeAndAfter();

  before(function() {
    this.fn = builtinGenerateFile;
  });



  describe('with no data', function() {

    before(function() {
      this.options = {
        rootPath: this.heap.alloc(),
        contents: 'foo'
      };
    });



    it('should trigger `success`', expect('success'));

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
    it('should not actually create a file', assert.fileDoesntExist);
  });


  describe('if file/folder already exists at `rootPath`', function() {
    before(function() {
      this.options = {
        contents: 'blah blah blah'
      };
    });

    describe('(file)', function() {
      // Create an extra file beforehand to simulate a collision
      before(function(cb) {
        this.options.rootPath = this.heap.alloc();
        this.heap.touch(this.options.rootPath, cb);
      });
      it('should trigger "alreadyExists" handler', expect({
        alreadyExists: true,
        success: 'Should not override existing file without `options.force`!'
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
        success: 'Should not override existing directory without `options.force`!'
      }));
    });

  });


  describe('if file/folder already exists and `force` option is true', function() {
    before(function() {
      this.options = {
        force: true,
        contents: 'blahhhh blahhhh blahhhh'
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
