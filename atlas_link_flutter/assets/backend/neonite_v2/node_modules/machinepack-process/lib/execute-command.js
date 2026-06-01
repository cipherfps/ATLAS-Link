module.exports = {


  friendlyName: 'Execute command',


  description: 'Execute a command like you would on the terminal.',


  extendedDescription:
  'This uses the `child_process.exec()` method from Node.js core to run the specified command. '+
  'The success exit from this machine will not be called until the command has finished running (i.e. the resulting child process exits). '+
  'If you need a more advanced/flexible interface, check out `spawnChildProcess()`.  It is much lower-level, and exposes raw access to the '+
  'child process instance. Also note that only errors which can be reliably determined cross-platform are included in this machine. '+
  'On *nix platforms (including OS X), you may be able to examine the `code` property of the object passed through the `error` exit '+
  'to determine the specific cause of an error (e.g. 127 for "command not found" or 126 for "command not executable").',


  moreInfoUrl: 'https://nodejs.org/api/child_process.html#child_process_child_process_exec_command_options_callback',


  inputs: {

    command: {
      description: 'The command to run, including any whitespace-delimited CLI args/opts.',
      example: 'ls -la',
      required: true
    },

    dir: {
      friendlyName: 'Working directory',
      description: 'The path to the directory where this command will be run.',
      extendedDescription: 'If not set, this defaults to the present working directory.  If a relative path is provided, it will be resolved relative to the present working directory.',
      example: '/Users/mikermcneil/foo'
    },

    environmentVars: {
      friendlyName: 'Environment variables',
      description: 'A dictionary of environment variables to provide to the child process.',
      extendedDescription: 'By default, the same environment variables as in the current process will be used.  If specified, the dictionary should consist of the name of each environment variable as a key, and the value of the variable on the right-hand side.  The value of any environment variable is always a string.',
      example: {}
    },

    timeout: {
      description: 'The maximum number of miliseconds to wait for this command to finish.',
      extendedDescription: 'By default, no time limit will be enforced.  Note that if the time limit is reached, SIGERM will be sent to the child process.',
      example: 60000
    }

  },


  exits: {

    success: {
      outputFriendlyName: 'Command output',
      outputDescription: 'The output returned from executing the command.',
      extendedDescription: 'Note that the output is split into that which came from "stdout" vs. that which came from "stderr".',
      outputExample: {
        stdout: '...',
        stderr: '...'
      },
    },

    notADir: {
      friendlyName: 'Not a directory',
      description: 'The specified path for the working directory pointed to something which is not a directory (e.g. a file or shortcut).'
    },

    forbidden: {
      description: 'The user running the machine had insufficient permissions to spawn process from the specified path.',
      extendedDescription: 'You might need to use `chown`/`chmod` to alter the permissions for the executable!'
    },

    noSuchDir: {
      friendlyName: 'No such directory',
      description: 'No directory could be found at the specified path for the working directory.'
    },

    timedOut: {
      description: 'The specified command was automatically killed because it had not finished before the configured time limit (`timeout`).',
      extendedDescription: 'Note that the command _may have already caused side effects_ before it was stopped.'
    },

  },


  fn: function (inputs,exits) {

    // Import `util` and `child_process.exec`
    var path = require('path');
    var executeCmdInChildProc = require('child_process').exec;

    // Import `lodash`.
    var _ = require('@sailshq/lodash');

    // First, build up the options to pass in to `child_process.exec()`.
    var childProcOpts = {};

    // Determine the appropriate `cwd` for `child_process.exec()`.
    if (inputs.dir === undefined) {
      // Default directory to current working directory
      childProcOpts.cwd = process.cwd();
    }
    else {
      // If a `dir` was specified, resolve it to make sure
      // it's an absolute path.
      childProcOpts.cwd = path.resolve(inputs.dir);
    }

    // Declare a var for holding the current timestamp, if a timeout was provided.
    var timestampBeforeExecutingCmd;

    // If `timeout` was provided...
    if (inputs.timeout !== undefined) {

      // If the timeout < 1 millisecond, return a validation error through our `error` exit.
      if (inputs.timeout < 1) {
        return exits.error('Invalid timeout (`'+inputs.timeout+'`).  Must be greater than zero.  Remember: `timeout` should be used to indicate the maximum number of miliseconds to wait for this command to finish before giving up.');
      }
      // Otherwise add the specified timeout as an option to the `exec` command.
      childProcOpts.timeout = inputs.timeout;
      // Record the current time so we can have an idea later if the executable timed out.
      timestampBeforeExecutingCmd = Date.now();
    }


    // If `environmentVars` were provided, pass them in to `child_process.exec()`.
    // (Otherwise, by default, the child process receives the parent process's `process.env`)
    if (inputs.environmentVars !== undefined) {
      // Notice that we carefully expose parent process's env variables to the
      // child process's environment, while still letting the deliberately passed-in
      // `environmentVars` take precedence.
      childProcOpts.env = _.extend({}, process.env, inputs.environmentVars);
    }



    // Now spawn the child process using the options that were passed in.
    executeCmdInChildProc(inputs.command, childProcOpts, function onClose(err, bufferedStdout, bufferedStderr) {
      // If an error occurred...
      if (err) {
        // console.log('err=>',err);
        // console.log('keys=>',Object.keys(err));
        // console.log('err.code=>',err.code);
        // console.log('err.killed=>',err.killed);
        // console.log('err.syscall=>',err.syscall);
        // console.log('err.errno=>',err.errno); // e.g. 127 || 'ENOENT'
        // console.log('err.signal=>',err.signal); // e.g. 'SIGTERM'

        // If it's not an object, we don't know how to handle it, so pass it straight through
        // the `error` exit.
        // `err.syscall.match(/spawn/i)` should be true as well, but not testing since
        // Node v0.12 changed this a bit back in the day... and you never know.
        if (!_.isObject(err)) {
          return exits.error(err);
        }

        // If we get an `ENOTDIR` error, it means the specified working directory
        // was invalid, so leave through the `notADir` exit.
        if (err.code==='ENOTDIR') {
          return exits.notADir();
        }

        // If we get an `ENOENT` error, it means the specified working directory
        // did not exist, so leave through the `noSuchDir` exit.
        if (err.code==='ENOENT') {
          return exits.noSuchDir();
        }

        // If we get an `ENOENT` error, it means that the current process (because
        // of the system user who ran it) has insufficient permissions to run the
        // command, so leave through the `forbidden` exit.
        if (err.code==='EACCES') {
          return exits.forbidden();
        }

        // Check to see if this error is because of the configured timeout.
        if (err.signal==='SIGTERM' && inputs.timeout) {
          // If so, leave through the `timedOut` exit.
          var msElapsed = Date.now() - timestampBeforeExecutingCmd;
          if (msElapsed >= inputs.timeout) {
            return exits.timedOut();
          }
        }

        // Forward all other errors through the `error` exit.
        err.stdout = bufferedStdout;
        err.stderr = bufferedStderr;
        return exits.error(err);
      }//•

      // Process exited successfully (exit code 0), so leave through the `success` exit,
      // using the buffered output.
      return exits.success({
        stdout: bufferedStdout,
        stderr: bufferedStderr
      });

    });//_∏_
  },



};
