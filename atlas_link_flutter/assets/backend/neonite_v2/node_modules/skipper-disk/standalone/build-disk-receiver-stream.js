/**
 * Module dependencies
 */

var WritableStream = require('stream').Writable;
var path = require('path');
var _ = require('@sailshq/lodash');
var fsx = require('fs-extra');
var buildProgressStream = require('./build-progress-stream');
var debug = require('debug')('skipper-disk');
var util = require('util');


/**
 * A simple receiver for Skipper that writes Upstreams to
 * disk at the configured path.
 *
 * Includes a garbage-collection mechanism for failed
 * uploads.
 *
 * @param  {Object} options
 * @return {Stream.Writable}
 */
module.exports = function buildDiskReceiverStream(options, adapter) {
  options = options || {};
  var log = options.log || function noOpLog(){};

  // if maxBytes is configed in "MB" ended string
  // convert it into bytes
  if (options.maxBytes) {
    var _maxBytesRegResult = (options.maxBytes + '').match(/(\d+)m/i);
    if (!_.isNull(_maxBytesRegResult)){
      options.maxBytes = _maxBytesRegResult[1] * 1024 * 1024;
    }
  };

  _.defaults(options, {

    // // The default `saveAs` implements a unique filename by combining:
    // //  • a generated UUID  (like "4d5f444-38b4-4dc3-b9c3-74cb7fbbc932")
    // //  • the uploaded file's original extension (like ".jpg")
    // saveAs: function(__newFile, cb) {
    //   return cb(null, UUIDGenerator.v4() + path.extname(__newFile.filename));
    // },

    // Bind a progress event handler, e.g.:
    // function (milestone) {
    //   milestone.id;
    //   milestone.name;
    //   milestone.written;
    //   milestone.total;
    //   milestone.percent;
    // },
    onProgress: undefined,

    // Upload limit (in bytes)
    // defaults to ~15MB
    maxBytes: 15000000,

    // By default, upload files to `./.tmp/uploads` (relative to cwd)
    dirname: '.tmp/uploads'
  });


  var receiver__ = WritableStream({ objectMode: true });

  // if onProgress handler was provided, bind an event automatically:
  if (_.isFunction(options.onProgress)) {
    receiver__.on('progress', options.onProgress);
  }

  // Track the progress of all file uploads that pass through this receiver
  // through one or more attached Upstream(s).
  receiver__._files = [];


  // This `_write` method is invoked each time a new file is received
  // from the Readable stream (Upstream) which is pumping filestreams
  // into this receiver.  (filename === `__newFile.filename`).
  receiver__._write = function onFile(__newFile, encoding, done) {

    // `skipperFd` is the file descriptor-- the unique identifier.
    // Often represents the location where file should be written.
    //
    // But note that we formerly used `fd`, but now Node attaches an `fd` property
    // to Readable streams that come from the filesystem.  So this kinda messed
    // us up.  And we had to do this instead:
    var skipperFd = __newFile.skipperFd || (_.isString(__newFile.fd)? __newFile.fd : undefined);
    if (!_.isString(skipperFd)) {
      return done(new Error('In skipper-disk adapter, write() method called with a stream that has an invalid `skipperFd`: '+skipperFd));
    }

    // If fd DOESNT have leading slash, resolve the path
    // from process.cwd()
    if (!skipperFd.match(/^\//)) {
      skipperFd = path.resolve(process.cwd(), '.tmp/uploads', skipperFd);
      __newFile.skipperFd = skipperFd;
    }

    // Ensure necessary parent directories exist:
    fsx.mkdirs(path.dirname(skipperFd), function(mkdirsErr) {
      // If we get an error here, it's probably because the Node
      // user doesn't have write permissions at the designated
      // path.
      if (mkdirsErr) {
        return done(mkdirsErr);
      }

      // Error reading from the file stream
      debug('binding error handler for incoming file in skipper-disk');
      __newFile.on('error', function(err) {
        debug('Read error on file '+__newFile.filename+ '::'+ util.inspect(err&&err.stack));
        log('***** READ error on file ' + __newFile.filename, '::', err);
      });

      // Create a new write stream to write to disk
      var outs__ = fsx.createWriteStream(skipperFd, encoding);

      // When the file is done writing, call the callback
      outs__.on('finish', function successfullyWroteFile() {
        log('finished file: ' + __newFile.filename);
        // File the file entry in the receiver with the same fd as the finished stream.
        var file = _.find(receiver__._files, {fd: skipperFd});
        if (file) {
          // Set the byteCount of the stream to the "total" value of the file, which has
          // been updated as the file was written.
          __newFile.byteCount = file.total;
        }
        // If we couldn't find the file in the receiver, that's super weird, but output
        // a notice and try to continue anyway.
        else {
          debug('Warning: received `finish` event for file `' + __newFile.filename + '` uploaded via field `' + __newFile.field + '`, but could not find a record of that file in the receiver.');
          debug('Was this a zero-byte file?');
          debug('Attempting to return the file anyway...');
        }
        // Indicate that a file was persisted.
        receiver__.emit('writefile', __newFile);
        done();
      });
      outs__.on('E_EXCEEDS_UPLOAD_LIMIT', function (err) {
        done(err);
      });

      // Create another stream that simply keeps track of the progress of the file stream and emits `progress` events
      // on the receiver.
      var __progress__ = buildProgressStream(options, __newFile, receiver__, outs__, adapter);

      // Forward any uncaught errors to the receiver.
      //
      // Note -- it's important to forward using `.emit` rather than calling `done()`, because if for some reason an error occurs
      // _after_ the receiver stream closes, calling the `done()` method will throw another error.
      // Skipper core handles errors on the receiver and can deal with those errors even after the receiver stream has closed.
      outs__.on('error', function(err) {
        var newError = new Error('Error writing file `' + skipperFd + '` to disk (for field `'+__newFile.field+'`): ' + util.inspect(err, {depth: 5}));
        receiver__.emit('error', newError);
      });
      __progress__.on('error', function(err) {
        var newError = new Error('Error reported from the progress stream while uploading file `' + skipperFd + '` (for field `'+__newFile.field+'`): ' + util.inspect(err, {depth: 5}));
        receiver__.emit('error', newError);
      });

      // Finally pipe the progress THROUGH the progress stream
      // and out to disk.
      __newFile
        .pipe(__progress__)
        .pipe(outs__);

    });

  };

  return receiver__;
}; // </DiskReceiver>
