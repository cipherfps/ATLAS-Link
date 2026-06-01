/**
 * Module dependencies
 */

var Pack = require('../');



/**
 * Note: These tests should ideally not be redis-specific.
 * (that way we can reuse them for any driver implementing the "cache" interface layer)
 */

describe('getCachedValue()', () => {

  // Used to hold manager and active connection throughout the tests below.
  var manager;
  var connection;


  // The keys to use during tests.
  var keysUsed = ['test1', 'test2', 'test3', 'test4', 'test5', 'test6', 'test7', 'test8'];

  //                                               _   _
  //                                              | | (_)
  // _ __   ___     ___ ___  _ __  _ __   ___  ___| |_ _  ___  _ __
  //| '_ \ / _ \   / __/ _ \| '_ \| '_ \ / _ \/ __| __| |/ _ \| '_ \
  //| | | | (_) | | (_| (_) | | | | | | |  __/ (__| |_| | (_) | | | |
  //|_| |_|\___/   \___\___/|_| |_|_| |_|\___|\___|\__|_|\___/|_| |_|
  //
  describe('with no connection', () => {
    it('should fail', (done) => {
      Pack.getCachedValue({
        connection: {},
        key: keysUsed[1]
      }).switch({
        error: done,
        badConnection: function (){
          return done();
        },
        notFound: function (){
          return done(new Error('Expecting `badConnection` exit'));
        },
        success: function (){
          return done(new Error('Expecting `badConnection` exit'));
        }
      });
    });
  });



  //  ╔╗ ╔═╗╔═╗╦╔═╗  ╦ ╦╔═╗╔═╗╔═╗╔═╗
  //  ╠╩╗╠═╣╚═╗║║    ║ ║╚═╗╠═╣║ ╦║╣
  //  ╚═╝╩ ╩╚═╝╩╚═╝  ╚═╝╚═╝╩ ╩╚═╝╚═╝
  describe('with basic usage', () => {


    //  ┌┐ ┌─┐┌─┐┌─┐┬─┐┌─┐
    //  ├┴┐├┤ ├┤ │ │├┬┘├┤
    //  └─┘└─┘└  └─┘┴└─└─┘ooo
    //
    // Beforehand, create a manager and acquire an initial active
    // connection from it.  Also delete the specified keys, just to be safe.
    before((done) => {
      Pack.createManager({
        connectionString: 'redis://127.0.0.1:6379',
        meta: {
          password: 'qwer1234'
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
    });//</before>
    it('should work', (done) => {
      Pack.cacheValue({
        connection: connection,
        key: keysUsed[0],
        value: 'whatever'
      }).switch({
        error: done,
        success: function (){
          Pack.getCachedValue({
            connection: connection,
            key: keysUsed[0]
          }).exec(done);
        }
      });
    });//</it should work>


    it('should exit `notFound` if key does not exist', (done) => {
      Pack.getCachedValue({
        connection: connection,
        key: keysUsed[1]
      }).switch({
        error: done,
        notFound: function (){
          return done();
        },
        success: function (){
          return done(new Error('Expecting `notFound` exit'));
        }
      });
    });//</it should exit `notFound` if key does not exist>


    it('should exit `notFound` if the key expired', (done) => {
      Pack.cacheValue({
        connection: connection,
        key: keysUsed[0],
        value: 'whatever',
        ttl: 1
      }).switch({
        error: done,
        success: function (){
          setTimeout(
            () => {
              Pack.getCachedValue({
                connection: connection,
                key: keysUsed[0]
              }).switch({
                error: done,
                notFound: function (){
                  return done();
                },
                success: function (){
                  return done(new Error('Expecting `notFound` exit'));
                }
              });
            }, 1100);
        }
      });
    });//</should exit `notFound` if the key expired>



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


  });//</with basic usage>


});


