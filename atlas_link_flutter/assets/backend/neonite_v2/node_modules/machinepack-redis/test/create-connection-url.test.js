/**
 * Module dependencies
 */

var assert = require('assert');
var Pack = require('../');
var shouldProperlyStoreValue = require('./helpers/should-properly-store-value.test-helper');


/**
 * Note: These tests should ideally not be redis-specific.
 * (that way we can reuse them for any driver implementing the "cache" interface layer)
 */

describe('createConnectionUrl()', () => {

  describe('with default inputs', () => {

    it ('should return the url redis://127.0.0.1:6379', () => {
      var url = Pack.createConnectionUrl().execSync();

      assert.equal(url, 'redis://127.0.0.1:6379');
    });

  });

  describe('with host \'redis2go.com\', port \'6380\', password \'secret\' and database \'15\'', () => {

    it ('should return the url redis://:secret@redis2go.com:6380/15', () => {
      var url = Pack.createConnectionUrl({
        host: 'redis2go.com',
        port: 6380,
        pass: 'secret',
        db: 15
      }).execSync();

      assert.equal(url, 'redis://:secret@redis2go.com:6380/15');
    });

  });


});


