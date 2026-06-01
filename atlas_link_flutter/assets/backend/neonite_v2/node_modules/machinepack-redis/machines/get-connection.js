module.exports = {
//
//
  friendlyName: 'Get connection',
  //
  //
  description: 'Get an active connection to Redis.',
  //
  //
  inputs: {
    //
    manager: {
      friendlyName: 'Manager',
      description: 'The connection manager instance to acquire the connection from.',
      extendedDescription:
        'Only managers built using the `createManager()` method of this driver are supported. ' +
        'Also, the database connection manager instance provided must not have been destroyed--' +
        'i.e. once `destroyManager()` is called on a manager, no more connections can be acquired ' +
        'from it (also note that all existing connections become inactive-- see `destroyManager()` ' +
        'for more on that).',
      example: '===',
      required: true
    },

    timeout: {
      friendlyName: 'Timeout',
      description: 'The amount of time, in milliseconds, to allow for a successful connection to take place.',
      example: 10000,
      defaultsTo: 15000
    },
    //
    meta: {
      friendlyName: 'Meta (custom)',
      description: 'Additional stuff to pass to the driver.',
      extendedDescription: 'This is reserved for custom driver-specific extensions.  Please refer to the documentation for the driver you are using for more specific information.',
      example: '==='
    }
    //
  },
  //
  //
  exits: {
    //
    success: {
      description: 'A connection was successfully acquired.',
      extendedDescription: 'This connection should be eventually released.  Otherwise, it may time out.  '+
        'It is not a good idea to rely on database connections timing out-- be sure to release this connection '+
        'when finished with it!\n'+
        '\n'+
        'In the report returned from this exit:\n'+
        ' + The `connection` property is an active connection to the database.\n'+
        ' + The `meta` property is reserved for custom driver-specific extensions.',
      outputFriendlyName: 'Report',
      outputDescription: 'A dictionary reporting any relevant output from this machine under these circumstances.',
      outputExample: {
        connection: '===',
        meta: '==='
      }
    },
    //
    failed: {
      description: 'Could not acquire a connection to the database using the specified manager.',
      extendedDescription: 'This might mean any of the following:\n' +
        ' + the credentials encoded in the connection string are incorrect\n' +
        ' + there is no database server running at the provided host (i.e. even if it is just that the database process needs to be started)\n' +
        ' + there is no software "database" with the specified name running on the server\n' +
        ' + the provided connection string does not have necessary access rights for the specified software "database"\n' +
        ' + this Node.js process could not connect to the database, perhaps because of firewall/proxy settings\n' +
        ' + any other miscellaneous connection error\n'+
        '\n'+
        'In the report returned from this exit:\n'+
        ' + The `error` property is a JavaScript Error instance explaining that a connection could not be made.\n'+
        ' + The `meta` property is reserved for custom driver-specific extensions.'+
        '',
      outputFriendlyName: 'Report',
      outputDescription: 'A dictionary reporting any relevant output from this machine under these circumstances.',
      outputExample: {
        error: '===',
        meta: '==='
      }
    }
    //
  },
  //
  //
  fn: function (inputs, exits){
    var _ = require('@sailshq/lodash');
    var redis = require('redis');
    var flaverr = require('flaverr');

    // Build a local variable (`redisClientOptions`) to house a dictionary
    // of additional Redis client options that will be passed into createClient().
    // (this is pulled from the `meta` mananger)
    //
    // For a complete list of available options, see:
    //  • https://github.com/NodeRedis/node_redis#options-is-an-object-with-the-following-possible-properties
    var redisClientOptions = inputs.manager.meta || {};

    // Declare a var to hold the Redis connection timeout identifier, so it can be cleared later.
    var redisConnectionTimeout;

    // Create Redis client
    var client;
    try {

      client = redis.createClient(inputs.manager.connectionString, redisClientOptions);
    } catch (e) {
      // If a "TypeError" was thrown, it means something was wrong with
      // one of the provided client options.  We assume the issue was with
      // the connection string, since this is the case 99% of the time.
      // Of course, the actual error is passed through, so it's possible to
      // tell what's going on if this is a data-type error related to some
      // other custom option passed in via `meta`.
      if (e.name === 'TypeError') {
        return exits.failed({error: new Error('Invalid Redis client options in manager. Details: ' + e.stack)});
      }
      return exits.failed({error: e});
    }

    ////////////////////////////////////////////////////////////////////////
    // These two functions (`onPreConnectionError`, `onPreConnectionEnd`)
    // have to be defined ahead of time (otherwise, they are not in scope
    // from within each other's implementations; and so cannot be used as
    // the second argument to `removeListener()`)
    var redisConnectionError;
    function onPreConnectionError (err){
      // If this is an authentication error (i.e. bad password), then
      // we won't be getting an `end` event, so we'll bail out immediately.
      if (err.command === 'AUTH' && err.code === 'WRONGPASS') {
        client.removeListener('end', onPreConnectionEnd);
        client.removeListener('error', onPreConnectionError);
        // Swallow follow-on errors.
        client.on('error', () => {});
        return exits.failed({
          error: flaverr('ERR_BAD_PASSWORD', new Error('The password supplied to the Redis server was incorrect.'))
        });
      }
      // If this is an authentication "info" event (i.e. NO password was supplied),
      // and the `authLater` meta key isn't `true`, bail out immediately.
      if (err.command === 'INFO' && err.code === 'NOAUTH' && (!inputs.meta || inputs.meta.authLater === true)) {
        client.removeListener('end', onPreConnectionEnd);
        client.removeListener('error', onPreConnectionError);
        // Swallow follow-on errors.
        client.on('error', () => {});
        return exits.failed({
          error: flaverr('ERR_NO_PASSWORD', new Error('The Redis server requires a password, but none was supplied.'))
        });
      }
      redisConnectionError = err;
    }
    function onPreConnectionEnd (){
      clearTimeout(redisConnectionTimeout);
      client.removeListener('end', onPreConnectionEnd);
      client.removeListener('error', onPreConnectionError);

      // Prevent automatic reconnection attempts.
      client.end(true);

      return exits.failed({
        error: redisConnectionError || new Error('Redis client fired "end" event before it finished connecting.')
      });
    }

    // Add a timeout for the initial Redis session connection.
    redisConnectionTimeout = setTimeout(() => {
      return exits.error(flaverr('E_REDIS_CONNECTION_TIMED_OUT', new Error('Took too long to connect to the specified Redis session server.\nYou can change the allowed connection time by setting the `timeout` input (currently ' + inputs.timeout + 'ms).')));
    }, inputs.timeout);

    ////////////////////////////////////////////////////////////////////////

    // Bind an "error" listener so that we can track errors that occur
    // during the connection process.
    client.on('error', onPreConnectionError);

    // Bind an "end" listener in case the client "ends" before
    // it successfully connects...
    client.on('end', onPreConnectionEnd);

    // Bind a "ready" listener so that we know when the client has connected.
    client.once('ready', () => {
      clearTimeout(redisConnectionTimeout);
      client.removeListener('end', onPreConnectionEnd);
      client.removeListener('error', onPreConnectionError);

      // Bind "error" handler to prevent crashing the process if error events
      // are emitted later on (e.g. if the Redis server crashes or the connection
      // is lost for any other reason).
      // See https://github.com/mikermcneil/waterline-query-builder/blob/master/docs/errors.md#when-a-connection-is-interrupted
      client.on('error', (err) => {
        // If manager was not provisioned with an `onUnexpectedFailure`,
        // we'll just handle this error event silently (to prevent crashing).
        if (!_.isFunction(inputs.manager.onUnexpectedFailure)) {
          return;
        }

        var errToSend = new Error;
        errToSend.connection = client;
        errToSend.failureType = 'error';

        if (err) {
          errToSend.originalError = err;
          if (/ECONNREFUSED/g.test(err)) {
            errToSend.message =
                'Error emitted from Redis client: Connection to Redis server was lost (ECONNREFUSED). ' +
                'Waiting for Redis client to come back online (if configured to do so, auto-reconnecting behavior ' +
                'is happening in the background). Currently there are ' + client.connections + ' underlying Redis connections.\n' +
                'Error details:' + err.stack;
          } else {
            errToSend.message = 'Error emitted from Redis client.\nError details:' + err.stack;
          }
        } else {
          errToSend.message = 'Error emitted from Redis client.\n (no other information available)';
        }

        inputs.manager.onUnexpectedFailure(errToSend);
      });

      client.on('end', () => {
        // If manager was not provisioned with an `onUnexpectedFailure`,
        // we'll just handle this error event silently (to prevent crashing).
        if (!_.isFunction(inputs.manager.onUnexpectedFailure)) {
          return;
        }

        var errToSend = new Error('Redis client disconnected.');
        errToSend.connection = client;
        errToSend.failureType = 'end';
        inputs.manager.onUnexpectedFailure(errToSend);

      });

      // Now track this Redis client as one of the "redisClients" on our manager
      // (since we want to be able to call destroyManager to wipe them all)
      inputs.manager.redisClients.push(client);

      // Save a reference to our manager instance on the redis client.
      if (client._fromWLManager) {
        return exits.error(new Error('Consistency violation: Somehow, a `_fromWLManager` key already exists on this Redis client instance!'));
      }
      client._fromWLManager = inputs.manager;

      // Finally, send back the Redis client as our active "connection".
      return exits.success({
        connection: client
      });
    });

  }


};
