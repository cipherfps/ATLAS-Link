/**
 * Module dependencies
 */

var assert = require('assert');
var _ = require('@sailshq/lodash');
var async = require('async');
var Pack = require('../');





describe('spawnChildProcess()', function (){




  describe('with basic usage', function(){
    var childProc;

    it('should work', function (done){
      var _childProc = Pack.spawnChildProcess({
        command: 'echo',
        cliArgs: ['hi there']
      }).execSync();
      childProc = _childProc;
      childProc.once('error', function whenFirstErrorIsEmitted(err){ return done(err); });
      return done();
    });

    after(function (done) {
      if (!childProc) { return done(); }

      Pack.killChildProcess({
        childProcess: childProc,
        forceIfNecessary: true
      }).exec(done);
    });
  });



  describe('when providing env vars', function(){
    var childProc;

    it('should still have access to env of parent process', function (done){

      // Set a couple of env vars in parent process.
      process.env.foobar = 'gee';
      process.env.beep = 'boop';

      // Used below for double-checking that we didn't inadvertentely corrupt
      // the parent process's environment.
      var envVarsBackup = _.cloneDeep(process.env);

      // Used below for verifying that the child proc had access to
      // the expected env vars.
      var conglomeratedBufferedStdout = '';

      // Now spawn child proc.
      var _childProc = Pack.spawnChildProcess({
        command: 'node',
        cliArgs: ['-e', 'console.log(process.env.foobar + \' \' + process.env.baz + process.env.beep);'],
        environmentVars: {
          baz: 'williker',
          beep: 's' // << to override the `beep` env var we set in our parent proc
        }
      }).execSync();
      childProc = _childProc;
      childProc.once('error', function whenFirstErrorIsEmitted(err){ return done(err); });

      // Receive output from the child process.
      childProc.stdout.on('data', function onStdoutData(tastyBytes){
        conglomeratedBufferedStdout += tastyBytes.toString();
      });

      // Wait for the child process to finish.
      childProc.on('close', function (){

        // Verify that `process.env` of parent process was not damaged.
        try { assert.deepEqual(envVarsBackup, process.env); }
        catch (e) { return done(e); }

        // If the child process logged "gee willikers\n", then that means it had access to both the env vars
        // that were specially passed in, AS WELL AS of its parent process.  It also means that it properly
        // overrode parent env vars with those that were explicitly passed in.
        try { assert.strictEqual('gee willikers\n', conglomeratedBufferedStdout); }
        catch (e) { return done(e); }

        return done();
      });
    });

    after(function (done) {
      if (!childProc) { return done(); }

      Pack.killChildProcess({
        childProcess: childProc,
        forceIfNecessary: true
      }).exec(done);
    });
  });



  describe('multiple child processes at once', function(){

    var childProcs = [];
    it('should work even with lots of child processes at once', function (done){

      // Spin up several child processes at once, tracking them using
      // the local variable defined above (`childProcs`) so it is available
      // for us in `after` below.
      async.each(_.range(15), function (i, next) {
        var _childProc = Pack.spawnChildProcess({
          command: 'echo',
          cliArgs: ['hi #'+i]
        }).execSync();
        // _childProc.stdout.on('data', function onData(data){ console.log('->',data.toString()); });
        _childProc.once('error', function whenFirstErrorIsEmitted(err){ return next(err); });
        childProcs.push(_childProc);
        return next();
      }, function afterwards(err){
        if (err) { return done(err); }
        return done();
      });
    });

    after(function (done) {
      // Now if we made it this far, kill all of the child processes
      // that we just spun up.
      async.each(childProcs, function (childProc, next){
        Pack.killChildProcess({
          childProcess: childProc,
          forceIfNecessary: true
        }).exec(next);
      }, done);
    });

  });//<multiple child processes at once>



  describe('if spaces are used in the command', function (){
    this.slow(1500);

    var childProc;
    it('should fail with an error', function (done){

      try {
        childProc = Pack.spawnChildProcess({
          command: 'blah blah, space separated command stuff isnt allowed see',
        }).execSync();
      }
      catch (unusedErr) {
        return done();
      }

      return done(new Error('Should have failed w/ an error!'));
    });

    after(function (done) {
      if (!childProc) { return done(); }

      Pack.killChildProcess({
        childProcess: childProc,
        forceIfNecessary: true
      }).exec(done);
    });

  });//</if spaces are used in the command>


  describe('if the child process emits an error', function (){
    this.slow(1500);

    var childProc;
    it('should not crash the process', function (done){
      childProc = Pack.spawnChildProcess({
        command: 'node',
        cliArgs: ['-e', 'throw new Error(\'oops\');'],
      }).execSync();
      // We wait another few moments just to be 100% sure.
      setTimeout(function (){
        return done();
      }, 250);
    });

    after(function (done) {
      if (!childProc) { return done(); }

      Pack.killChildProcess({
        childProcess: childProc,
        forceIfNecessary: true
      }).exec(done);
    });

  });//</if the child process emits an error>



  describe('when the child process exits', function (){
    this.slow(3000);

    var childProc;

    it('should not crash the process', function (done){
      var _childProc = Pack.spawnChildProcess({
        command: 'sleep',
        cliArgs: ['1']
      }).execSync();
      childProc = _childProc;
      childProc.once('error', function whenFirstErrorIsEmitted(err){ return done(err); });

      // Wait for the child process to finish.
      childProc.on('close', function (){
        return done();
      });

    });

    after(function (done) {
      if (!childProc) { return done(); }

      Pack.killChildProcess({
        childProcess: childProc,
        forceIfNecessary: true
      }).exec(done);
    });
  });//</when the child process exits>



});
