module.exports = {


  friendlyName: 'Kill child process',


  description: 'Gracefully kill a running child process.',


  extendedDescription: 'This uses the `.kill()` instance method from Node.js core.  By default, SIGTERM is used.',


  moreInfoUrl: 'https://nodejs.org/api/child_process.html#child_process_child_kill_signal',


  sideEffects: 'idempotent',


  inputs: {

    childProcess: {
      description: 'The child process to kill.',
      example: '===',
      required: true
    },

    forceIfNecessary: {
      friendlyName: 'Force if necessary?',
      description: 'If set, then force the child process to exit if it cannot be killed gracefully (e.g. because it is already dead).',
      extendedDescription: 'If set, this method will first attempt to shut down the child process gracefully (SIGTERM); but if that doesn\'t work after a few milliseconds (`maxMsToWait`), it will use the nuclear option (SIGKILL) to kill the child process with no exceptions.',
      example: false,
      defaultsTo: false
    },

    maxMsToWait: {
      friendlyName: 'Timeout',
      description: 'The maximum number of miliseconds to wait for the child process to shut down gracefully.',
      example: 500,
      defaultsTo: 500
    }

  },


  exits: {

    success: {
      description: 'The child process was killed successfully.',
      outputDescription: 'Whether or not the child process had to be force-killed with "SIGKILL".',
      outputFriendlyName: 'Was force killed?',
      outputExample: false
    },

    invalidChildProcess: {
      description: 'The specified value was not a valid child process instance.',
      extendedDescription: 'You can obtain a child process instance by calling `spawnChildProcess()`.'
    },

    couldNotKill: {
      description: 'The child process could not be killed gracefully.',
      extendedDescription:
        'It might be refusing to close, it might already finished running, or it might even never have been alive.'+
        'To force-kill it using SIGKILL (e.g. `kill -9`), run this machine again with `force: true`.',
    },

  },


  fn: function (inputs,exits) {

    // Import `lodash`.
    var _ = require('@sailshq/lodash');

    // Validate that the provided child process instance is at least close to the real deal.
    if (!_.isObject(inputs.childProcess) || !_.isFunction(inputs.childProcess.kill) || !_.isFunction(inputs.childProcess.on) || !_.isFunction(inputs.childProcess.removeListener)) {
      // If not, leave through the `invalidChildProcess` exit.
      return exits.invalidChildProcess();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // For posterity: The difference between SIGKILL, SIGTERM, and SIGINT:
    //
    // • SIGKILL
    //   ° Like running `kill -9`.
    //   ° Can't listen for this, because it kills the process before you have a chance to do anything.
    //
    // • SIGTERM   (recommended)
    //   ° Like running `kill`.
    //   ° Allows graceful shutdown.
    //
    // • SIGINT
    //   ° Like hitting CTRL+C.
    //   ° Allows graceful shutdown.
    //
    // > The above was based on the great explanation at https://www.exratione.com/2013/05/die-child-process-die/#considering-unix-signals.
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


    // Set up some variables for use below.
    // (they need to be declared up here so they can reach each other)
    var forceKillOrGiveUp;
    var handleClosingChildProc;
    var timer;

    // Define a function (`forceKillOrGiveUp`) that will be called if the graceful shutdown attempt fails.
    forceKillOrGiveUp = function (){
      try {
        // Remove the `close` listener from the child process, so that it's not called later
        // if that signal comes in belatedly.  (And so we don't leave dangling listeners hanging around.)
        inputs.childProcess.removeListener('close', handleClosingChildProc);

        // If `forceIfNecessary` is on, attempt to send a SIGKILL to the process,
        // and return through the `success` exit with a `true` value indicating that
        // the process was force-killed.
        if (inputs.forceIfNecessary) {
          inputs.childProcess.kill('SIGKILL');
          return exits.success(true);
        }
        // Otherwise exit through `couldNotKill`.
        else {
          return exits.couldNotKill();
        }
      }
      // If any errors occurred attempting to clean up the process, forward them through
      // the `error` exit.
      catch (e) {
        return exits.error(e);
      }
    };

    // Define a function (`handleClosingChildProc`) that will be called when/if we receive a message
    // indicating that the child process has closed.
    handleClosingChildProc = function (code, signal) {
      // Ignore SIGKILL.
      // (if we're seeing it here, it came from somewhere else, and we don't want to get confused).
      if (signal === 'SIGKILL') {
        return;
      }

      // Remove the `close` listener from the child process, so that we don't leave any
      // event listeners dangling.
      inputs.childProcess.removeListener('close', handleClosingChildProc);

      // Clear the timeout timer.
      clearTimeout(timer);

      // Graceful kill successful!  Return `false` through the `success` exit to indicate a graceful shutdown.
      return exits.success(false);
    };


    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // > After a couple of hours of testing with both Node v4.3.0 and v5.4.0, my conclusion is that this
    // > optimization is a no-go for now (the `connected` flag doesn't appear to be reliable for this use case).
    // > That said, the commented-out section below will stay, and it can be brought back at the time we figure
    // > out a better way to do this; or if the behavior of Node core changes.
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // // If the child process is not "connected", then don't even bother trying to signal
    // // it to close gracefully (b/c it won't work).  Instead, just go ahead and either
    // // force-kill it or give up, depending on the `forceIfNecessary` input.
    // // (for more information about `connected`, see: https://nodejs.org/api/child_process.html#child_process_child_connected)
    // if (!inputs.childProcess.connected) {
    //   return forceKillOrGiveUp();
    // }
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Listen for the child process being closed.
    inputs.childProcess.once('close', handleClosingChildProc);

    // Set a timer.
    // (If the child process has not closed gracefully after `inputs.maxMsToWait`,
    //  then we need to either force kill it with SIGKILL, or fail via the
    //  `couldNotKill` exit).
    timer = setTimeout(forceKillOrGiveUp, inputs.maxMsToWait);


    // Now attempt to kill the child process gracefully (send SIGTERM).
    inputs.childProcess.kill();

  },



};
