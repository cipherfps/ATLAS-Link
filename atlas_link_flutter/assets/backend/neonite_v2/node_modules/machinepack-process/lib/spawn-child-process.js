module.exports = {


  friendlyName: 'Spawn child process',


  description: 'Spawn a child process and have it run a command.',


  extendedDescription:
  'This method should only be used when low-level access to the raw child process instance is necessary.  Instead, when possible, use `executeCommand()`-- '+
  'it has a much easier and much less error-prone interface. This method, on the other hand, uses the `child_process.spawn()` method from Node.js core. '+
  'The success exit from this machine will be called BEFORE the command has finished running (i.e. before the resulting child process exits). '+
  'Note that it is _very important_ that this method is synchronous, to ensure that the child process instance returned is available in time to bind '+
  'events.',


  moreInfoUrl: 'https://nodejs.org/api/child_process.html#child_process_child_process_spawn_command_args_options',


  sync: true,


  inputs: {

    command: {
      description: 'The command to run in the child process, without any CLI arguments or options.',
      extendedDescription: 'Node core is tolerant of CLI args mixed in with the main "command" in `child_process.exec()`, but it is not so forgiving when using `child_process.spawn()`.  That means you cannot provide a command like "git commit" this way.  Instead, provide "git" as the command and `["commit"]` as the CLI args.',
      example: 'ls',
      required: true
    },

    cliArgs: {
      friendlyName: 'CLI args/opts',
      description: 'An array of serial command-line arguments (e.g. `commit` or `install`) and/or options (e.g. `-al` or `-f 7` or `--foo=\'bar\'`) to pass in.',
      example: ['-la'],
      defaultsTo: []
    },

    dir: {
      friendlyName: 'Run from...',
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

  },


  exits: {

    success: {
      outputFriendlyName: 'Child process',
      outputDescription: 'A Node child process instance.',
      moreInfoUrl: 'https://nodejs.org/api/child_process.html#child_process_class_childprocess',
      extendedDescription: 'By the time it is returned, a no-op `error` listener has already been bound to prevent accidental crashing in the event of an unexpected error.',
      outputExample: '===',
    },

  },


  fn: function (inputs,exits) {

    // Import `path`.
    var path = require('path');

    // Import `child_process.spawn`.
    var spawn = require('child_process').spawn;

    // Import `lodash`.
    var _ = require('@sailshq/lodash');

    // First, validate that the provided command is valid.
    // `child_process.spawn()` has some pretty harsh limitations here,
    // and since this interface is so low level, it's really easy to mess up.
    if (inputs.command.match(/\s/)) {
      return exits.error(new Error('The string provided to spawnChildProcess() for the `command` input ("'+inputs.command+'") is not valid.  Unlike `executeCommand()` (the simpler, higher-level machine), the `command` provided to `spawnChildProcess()` should never contain spaces!  To spawn a child process with a command like `git commit`, send in "git" as the command, and `["commit", "-am", "foo"]` as the CLI args.'));
    }

    // Now build up the options to pass in to `child_process.spawn()`.
    var childProcOpts = {};

    // Determine the appropriate `cwd` for `child_process.spawn()`.
    if (inputs.dir === undefined) {
      // Default directory to current working directory
      childProcOpts.cwd = process.cwd();
    }
    else {
      // If a `dir` was specified, resolve it to make sure
      // it's an absolute path.
      childProcOpts.cwd = path.resolve(inputs.dir);
    }

    // If `environmentVars` were provided, get ready to pass them in to `child_process.spawn()`.
    // (Otherwise, by default, the child process receives the parent process's `process.env`)
    if (inputs.environmentVars !== undefined) {
      // Notice that we carefully expose parent process's env variables to the
      // child process's environment, while still letting the deliberately passed-in
      // `environmentVars` take precedence.
      childProcOpts.env = _.extend({}, process.env, inputs.environmentVars);
    }

    // Then spawn the child process.
    var liveChildProc = spawn(inputs.command, inputs.cliArgs, childProcOpts);

    // Set up a no-op error listener to prevent crashing.
    var wheneverAnErrorIsEmitted = function (err){ /* ... */ };//eslint-disable-line handle-callback-err, no-unused-vars
    liveChildProc.on('error', wheneverAnErrorIsEmitted);

    // But because we're binding that no-op error listener, we'll also need to bind
    // a one-time-use `close` listener; purely to _unbind_ our `error` listener.
    liveChildProc.once('close', function (){
      liveChildProc.removeListener('error', wheneverAnErrorIsEmitted);
    });

    // Return live child process through the `success` exit.
    return exits.success(liveChildProc);
  },



};
