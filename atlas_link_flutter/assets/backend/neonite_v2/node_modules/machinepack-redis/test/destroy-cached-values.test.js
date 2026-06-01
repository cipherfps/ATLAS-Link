/**
 * Module dependencies
 */

var Pack = require('../');



/**
 * Note: These tests should ideally not be redis-specific.
 * (that way we can reuse them for any driver implementing the "cache" interface layer)
 */

describe('destroyCachedValues()', () => {

  // Used to hold manager and active connection throughout the tests below.
  var manager;
  var connection;


  // The keys to use during tests.
  var keysUsed = ['machinepack-redis.test1', 'machinepack-redis.test2', 'machinepack-redis.test3', 'machinepack-redis.test4', 'machinepack-redis.test5', 'machinepack-redis.test6', 'machinepack-redis.test7', 'machinepack-redis.test8'];


  //  ┌┐ ┌─┐┌─┐┌─┐┬─┐┌─┐
  //  ├┴┐├┤ ├┤ │ │├┬┘├┤
  //  └─┘└─┘└  └─┘┴└─└─┘ooo
  //
  // Beforehand, create a manager and acquire an initial active
  // connection from it.
  before((done) => {
    Pack.createManager({
      connectionString: 'redis://127.0.0.1:6379',
      meta: {
        auth_pass: 'qwer1234'//eslint-disable-line camelcase
        // ^^use alternative option
      }
    }).switch({
      error: done,
      success: function (report){
        // Save reference to manager.
        manager = report.manager;

        Pack.getConnection({
          manager: manager
        }).switch({
          error: done,
          success: function (report){
            // Save reference to connection.
            connection = report.connection;

            // Now delete keys just to be safe.
            Pack.destroyCachedValues({
              connection: connection,
              keys: keysUsed
            }).exec(done);
          }
        });
      }
    });
  }); //</before>



  //  ╔╗ ╔═╗╔═╗╦╔═╗  ╦ ╦╔═╗╔═╗╔═╗╔═╗
  //  ╠╩╗╠═╣╚═╗║║    ║ ║╚═╗╠═╣║ ╦║╣
  //  ╚═╝╩ ╩╚═╝╩╚═╝  ╚═╝╚═╝╩ ╩╚═╝╚═╝
  describe('with basic usage', () => {


    it('should work', (done) => {

      Pack.cacheValue({
        connection: connection,
        key: 'test1',
        value: 'testValue'
      }).exec(() => {
        // Now delete keys just to be safe.
        Pack.destroyCachedValues({
          connection: connection,
          keys: ['test1']
        }).exec(() => {
          // Try to get the value from the cache
          Pack.getCachedValue({
            connection: connection,
            key: 'test1'
          }).switch({
            error: done,
            notFound: function (){
              return done();
            },
            success: function (){
              return done(new Error('Expecting `notFound` exit'));
            }
          });
        });
      });

    });//</it should work>

    it('should delete keys even if they do not exit', (done) => {

      Pack.cacheValue({
        connection: connection,
        key: 'test1',
        value: 'testValue'
      }).exec(() => {
        // Now delete keys just to be safe.
        Pack.destroyCachedValues({
          connection: connection,
          keys: ['test1']
        }).exec(() => {
          // Try to get the deleted key from the cache
          Pack.getCachedValue({
            connection: connection,
            key: 'test1'
          }).switch({
            error: done,
            notFound: function (){
              // Try to get the non existing key from the cache
              Pack.getCachedValue({
                connection: connection,
                key: 'nonexistingkey'
              }).switch({
                error: done,
                notFound: function (){
                  return done();
                },
                success: function (){
                  return done(new Error('Expecting `notFound` exit'));
                }
              });
            },
            success: function (){
              return done(new Error('Expecting `notFound` exit'));
            }
          });
        });
      });

    });//</it should delete keys even if they do not exit>

    it('should fail when passed a string', (done) => {

      Pack.destroyCachedValues({
        connection: connection,
        keys: 'somekeytodelete'
      }).switch({
        error: function (unusedErr){
          return done();
        },
        invalidKeys: function (report) { return done(new Error('Expecting `error` exit')); },
        failed:  function (report) { return done(new Error('Expecting `error` exit')); },
        badConnection:  function (report) { return done(new Error('Expecting `error` exit')); },
        success: function (report){ return done(new Error('Expecting `error` exit')); }

      });

    });//</should fail when passed a string>

    it('should fail when passed a number', (done) => {

      Pack.destroyCachedValues({
        connection: connection,
        keys: 1
      }).switch({
        error: function (unusedErr){
          return done();
        },
        invalidKeys: function (report) { return done(new Error('Expecting `error` exit')); },
        failed:  function (report) { return done(new Error('Expecting `error` exit')); },
        badConnection:  function (report) { return done(new Error('Expecting `error` exit')); },
        success: function (report){ return done(new Error('Expecting `error` exit')); }
      });

    });//</it should fail when passed a number>

    it('should fail when passed a dictionary', (done) => {

      Pack.destroyCachedValues({
        connection: connection,
        keys: {}
      }).switch({
        error: function (unusedErr){
          return done();
        },
        invalidKeys: function (report) { return done(new Error('Expecting `error` exit')); },
        failed:  function (report) { return done(new Error('Expecting `error` exit')); },
        badConnection:  function (report) { return done(new Error('Expecting `error` exit')); },
        success: function (report){ return done(new Error('Expecting `error` exit')); }
      });

    });//</it should fail when passed a dictionary>

  });//</with basic usage>


  //  ┌─┐┌─┐┌┬┐┌─┐┬─┐
  //  ├─┤├┤  │ ├┤ ├┬┘
  //  ┴ ┴└   ┴ └─┘┴└─ooo
  // Afterwards, destroy the keys that were set, and then also destroy the manager
  // (which automatically releases any connections).
  after((done) => {
    Pack.destroyCachedValues({
      connection: connection,
      keys: keysUsed
    }).exec((err) => {
      // If there is an error deleting keys, log it but don't stop
      // (we need to be sure and destroy the manager)
      if (err) {
        console.error('ERROR: Could not destroy keys in test cleanup.  Details:\n', err);
      }
      Pack.destroyManager({
        manager: manager
      }).exec(done);
    });
  });//</after>

});
