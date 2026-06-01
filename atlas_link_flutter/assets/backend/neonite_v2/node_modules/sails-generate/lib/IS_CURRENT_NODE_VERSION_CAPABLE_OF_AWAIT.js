/**
 * IS_CURRENT_NODE_VERSION_CAPABLE_OF_AWAIT()
 *
 * @type {Boolean}
 */

var RX_NODE_MAJOR_DOT_MINOR = /^v([^.]+)\.([^.]+)\./;
var major = +(process.version.match(RX_NODE_MAJOR_DOT_MINOR)[1]);
var minor = +(process.version.match(RX_NODE_MAJOR_DOT_MINOR)[2]);
module.exports = (major >= 8) || (major >= 7 && minor >= 9);

