module.exports = {
//
//
  friendlyName: 'Create manager',
  //
  //
  description: 'Build and initialize a connection manager instance for this Redis database.',
  //
  //
  extendedDescription:
    'The `manager` instance returned by this method contains any configuration that is necessary ' +
    'for communicating with the database and establishing connections (e.g. host, user, password) ' +
    'as well as any other relevant metadata.  The manager will often also contain a reference ' +
    'to some kind of native container (e.g. a connection pool).\n' +
    '\n' +
    'Note that a manager instance does not necessarily need to correspond with a pool though--' +
    'it might simply be a container for storing config, or it might refer to multiple pools ' +
    '(e.g. a PoolCluster from felixge\'s `mysql` package).',
  //
  moreInfoUrl: 'https://github.com/NodeRedis/node_redis#rediscreateclient',
  //
  //
  inputs: {
    //
    connectionString: {
      description: 'A string containing all metadata and credentials necessary for connecting to the Redis database.',
      example: 'redis://:secret@127.0.0.1:6379/12',
      required: true
    },
    //
    onUnexpectedFailure: {
      description: 'A function to call any time an unexpected error event is received from this manager or any of its connections.',
      extendedDescription:
        'This can be used for anything you like, whether that\'s sending an email to devops, ' +
        'or something as simple as logging a warning to the console.\n' +
        '\n' +
        'For example:\n' +
        '```\n' +
        'onUnexpectedFailure: function (err) {\n' +
        '  console.warn(\'Unexpected failure in database manager:\',err);\n' +
        '}\n' +
        '```',
      example: '->'
    },
    //
    meta: {
      friendlyName: 'Meta (custom)',
      description: 'Additional Redis-specific options to use when connecting.',
      extendedDescription: 'If specified, should be a dictionary.',
      moreInfoUrl: 'https://github.com/NodeRedis/node_redis#options-is-an-object-with-the-following-possible-properties',
      example: '==='
    }
    //
  },
  //
  //
  exits: {
    //
    success: {
      description: 'The manager was successfully created.',
      extendedDescription:
        'The new manager should be passed in to `getConnection()`.' +
        'Note that _no matter what_, this manager must be capable of ' +
        'spawning an infinite number of connections (i.e. via `getConnection()`).  ' +
        'The implementation of how exactly it does this varies on a driver-by-driver ' +
        'basis; and it may also vary based on the configuration passed into the `meta` input.',
      outputFriendlyName: 'Report',
      outputDescription: 'The `manager` property is a manager instance that will be passed into `getConnection()`. The `meta` property is reserved for custom driver-specific extensions.',
      outputExample: {
        manager: '===',
        meta: '==='
      }
    },
    //
    malformed: {
      description: 'The provided connection string is not valid for MySQL.',
      outputFriendlyName: 'Report',
      outputDescription: 'The `error` property is a JavaScript Error instance explaining that (and preferably "why") the provided connection string is invalid.  The `meta` property is reserved for custom driver-specific extensions.',
      outputExample: {
        error: '===',
        meta: '==='
      }
    },
    //
    failed: {
      description: 'Could not create a connection manager for this database using the specified connection string.',
      extendedDescription:
        'If this exit is called, it might mean any of the following:\n' +
        ' + the credentials encoded in the connection string are incorrect\n' +
        ' + there is no database server running at the provided host (i.e. even if it is just that the database process needs to be started)\n' +
        ' + there is no software "database" with the specified name running on the server\n' +
        ' + the provided connection string does not have necessary access rights for the specified software "database"\n' +
        ' + this Node.js process could not connect to the database, perhaps because of firewall/proxy settings\n' +
        ' + any other miscellaneous connection error\n' +
        '\n' +
        'Note that even if the database is unreachable, bad credentials are being used, etc, ' +
        'this exit will not necessarily be called-- that depends on the implementation of the driver ' +
        'and any special configuration passed to the `meta` input. e.g. if a pool is being used that spins up ' +
        'multiple connections immediately when the manager is created, then this exit will be called if any of ' +
        'those initial attempts fail.  On the other hand, if the manager is designed to produce adhoc connections, ' +
        'any errors related to bad credentials, connectivity, etc. will not be caught until `getConnection()` is called.',
      outputFriendlyName: 'Report',
      outputDescription: 'The `error` property is a JavaScript Error instance with more information and a stack trace.  The `meta` property is reserved for custom driver-specific extensions.',
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
    var Url = require('url');
    var _ = require('@sailshq/lodash');

    // Ensure that, if provided, `meta` is a dictionary.
    // This will be used as additional Redis client options.
    if (inputs.meta !== undefined) {
      if (!_.isObject(inputs.meta) || _.isFunction(inputs.meta)) {
        return exits.error('If provided, `meta` must be a dictionary.');
      }
    }

    // Validate connection string (call `malformed` if invalid).
    try {
      Url.parse(inputs.connectionString);
    } catch (e) {
      e.message =
        'Provided value (`' + inputs.connectionString + '`) is not a valid Redis connection string: ' +
        e.message;
      return exits.malformed({
        error: e
      });
    }

    // Finally, build and return the manager.
    var mgr = {
      meta: inputs.meta,
      connectionString: inputs.connectionString,
      onUnexpectedFailure: inputs.onUnexpectedFailure,
      // We set up an empty array for our redis clients, since we need to
      // track them in order to ensure calling destroyManager() kills them all.
      redisClients: []
    };
    return exits.success({
      manager: mgr
    });

  }


};
