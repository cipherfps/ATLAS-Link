// This is a boilerplate file which should not need to be changed.
module.exports = require('machine').pack({
  pkg: require('./package.json'),
  dir: __dirname
});



//... well except for this.
// Also give the driver a `redis` property, so that it provides access
// to the static Redis client library for Node.js. (See http://npmjs.com/package/redis)
module.exports.redis = require('redis');
