module.exports = {
//
//
  friendlyName: 'Create connection URL',
  //
  //
  sync: true,
  //
  //
  description: 'Build a Redis connection URL out of a dictionary of connection options.',
  //
  //
  inputs: {
    //
    host: {
      description: 'The host (IP or domain) on which the Redis server is running.',
      example: '127.0.0.1',
      defaultsTo: '127.0.0.1'
    },
    //
    port: {
      description: 'The port on which the Redis server is running.',
      example: '6379',
      defaultsTo: '6379'
    },
    //
    pass: {
      description: 'The password (if any) for the Redis server.',
      example: 'iheartredis'
    },
    //
    db: {
      description: 'The index of the database to connect to.',
      example: 123
    }
    //
  },
  //
  //
  exits: {
    //
    success: {
      outputFriendlyName: 'Redis URL',
      outputDescription: 'A fully-qualified URL for connecting to a Redis server.',
      outputExample: 'redis://:secret@127.0.0.1:6379/12'
    },
    //
  },
  //
  //
  fn: function (inputs, exits){

    // Every Redis URL starts with 'redis://'.
    var url = 'redis://';

    // Add the optional password.
    if (inputs.pass) {
      url += ':' + inputs.pass + '@';
    }

    // Add the host.
    url += inputs.host;

    // Add the port.
    url += ':' + inputs.port;

    // Add the optional database.
    if (inputs.db) {
      url += '/' + inputs.db;
    }

    // Return the finished URL through the "success" exit.
    return exits.success(url);

  }


};
