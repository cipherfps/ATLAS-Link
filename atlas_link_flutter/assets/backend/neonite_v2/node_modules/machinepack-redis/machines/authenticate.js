module.exports = {


  friendlyName: 'Authenticate',


  description: 'Authenticate an active connection with its connected Redis server.',


  sideEffects: 'idempotent',
  //
  //
  inputs: {
    //
    connection: {
      friendlyName: 'Connection',
      description: 'An active Redis connection.',
      extendedDescription: 'The provided Redis connection instance must still be active.  Only Redis connection instances created by the `getConnection()` machine in this driver are supported.',
      example: '===',
      required: true
    },
    //
    password: {
      friendlyName: 'Password',
      description: 'The password to pass to a connection for authentication',
      extendedDescription: 'The password to pass to a connection for authentication',
      required: true,
      example: 'mysupercomplexpass'
    },
    //
    meta: {
      friendlyName: 'Meta (custom)',
      description: 'Additional metadata to pass to the driver.',
      extendedDescription: 'This input is not currently in use, but is reserved for driver-specific customizations in the future.',
      example: '==='
    }
    //
  },
  //
  //
  exits: {
    //
    success: {
      description: 'The authentication process succeeded.',
      outputFriendlyName: 'Report',
      outputDescription: 'The `meta` property is reserved for custom driver-specific extensions.',
      outputExample: {
        meta: '==='
      }
    },
    //
    failed: {
      description: 'The attempt to authenticate failed.',
      outputFriendlyName: 'Report',
      outputDescription: 'The `error` property is a JavaScript Error instance with more information and a stack trace.  The `meta` property is reserved for custom driver-specific extensions.',
      outputExample: {
        error: '===',
        meta: '==='
      }
    },
    //
    badConnection: require('../constants/badConnection.exit')
    //
  },


  fn: function (inputs, exits){
    var _ = require('@sailshq/lodash');

    // Ducktype provided "connection" (which is actually a redis client)
    if (!_.isObject(inputs.connection) || !_.isFunction(inputs.connection.end) || !_.isFunction(inputs.connection.removeAllListeners)) {
      return exits.badConnection();
    }

    // Provided `connection` is a redis client.
    var redisClient = inputs.connection;

    redisClient.auth(inputs.password, (err)=>{
      if (err) {
        if (err.message === '') {
          return exits.failed({error: 'There was an error authenticating:' + err.message + '.' + err.stack});
        }
        return exits.error(err);
      }
      return exits.success();
    });//_∏_

  }

};
