module.exports = {


  friendlyName: 'Release connection',


  description: 'Close an active connection to the Redis server.',


  moreInfoUrl: 'https://github.com/NodeRedis/node_redis#clientendflush',


  sideEffects: 'idempotent',


  inputs: {

    connection: {
      friendlyName: 'Connection',
      description: 'An active Redis connection.',
      extendedDescription: 'The provided Redis connection instance must still be active.  Only Redis connection instances created by the `getConnection()` machine in this driver are supported.',
      example: '===',
      required: true
    },

    meta: {
      friendlyName: 'Meta (custom)',
      description: 'Additional metadata to pass to the driver.',
      extendedDescription: 'This input is not currently in use, but is reserved for driver-specific customizations in the future.',
      example: '==='
    }

  },


  exits: {

    success: {
      description: 'The connection was released and is no longer active.',
      extendedDescription: 'The provided connection may no longer be used for any subsequent queries.\n'+
        'In the report returned from this exit:\n'+
        ' + The `meta` property is reserved for custom driver-specific extensions.',
      outputFriendlyName: 'Report',
      outputDescription: 'A dictionary reporting any relevant output from this machine under these circumstances.',
      outputExample: {
        meta: '==='
      }
    },

    badConnection: require('../constants/badConnection.exit')

  },


  fn: function (inputs, exits) {
    var _ = require('@sailshq/lodash');

    // Validate provided connection (which is actually a redis client)
    if ( !_.isObject(inputs.connection) || !_.isFunction(inputs.connection.end) || !_.isFunction(inputs.connection.removeAllListeners) ) {
      return exits.badConnection();
    }

    // Grab a reference to the manager instance we piggybacked on this redis client.
    var mgr = inputs.connection._fromWLManager;

    // Release connection.
    try {
      inputs.connection.end(true);

      // If necessary, we could also do the following here:
      // inputs.connection.removeAllListeners();
      //
      // (but not doing that unless absolutely necessary because it could cause crashing
      //  of the process if our `redis` dep decides to emit any surprise "error" events.)
    }
    catch (e) {
      return exits.error(e);
    }

    // Remove this redis client from the manager.
    var foundAtIndex = mgr.redisClients.indexOf(inputs.connection);
    if (foundAtIndex === -1) {
      return exits.badConnection({
        meta: new Error('Attempting to release connection that is no longer referenced by its manager.')
      });
    }
    mgr.redisClients.splice(foundAtIndex, 1);

    // And that's it!
    return exits.success();

  }


};
