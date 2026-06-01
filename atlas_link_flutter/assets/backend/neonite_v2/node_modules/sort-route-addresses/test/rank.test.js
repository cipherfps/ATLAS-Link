var assert = require('assert');
var _ = require('@sailshq/lodash');

var sortRouteAddresses = require('../');

describe('Given an unordered list of Sails/Express-style route addresses',
function() {

  it('the addresses should be sorted by their inclusivity',
function() {

    var addresses = [
      '/*',
      'GET /*',
      '/*/baz',
      '/*/baz/*',
      '/*/bar/baz',
      '/:foo/*',
      '/:foo/:bar/*',
      'r|^/foo/\\d+$|',
      '/:foo/:bar/:baz',
      '/:foo/:bar/baz',
      '/:foo/:bar',
      '/:foo/bar/:baz',
      '/:foo/bar/baz',
      '/:foo/bar',
      '/:foo',
      '/foo/*',
      '/foo/*/baz',
      '/foo/:bar/:baz',
      '/foo/:bar/baz',
      '/foo/:bar',
      '/foo/bar/*',
      'GET /foo/bar/*',
      '/foo/bar/:baz',
      'GET /foo/bar/:baz',
      '/foo/bar/baz',
      '/foo/bar',
      '/foo',
      'GET /foo'
    ];

    var expected = ['GET /foo',
      '/foo',
      '/foo/bar',
      '/foo/bar/baz',
      'GET /foo/bar/:baz',
      '/foo/bar/:baz',
      'GET /foo/bar/*',
      '/foo/bar/*',
      '/foo/:bar',
      '/foo/:bar/baz',
      '/foo/:bar/:baz',
      '/foo/*/baz',
      '/foo/*',
      '/:foo/bar',
      '/:foo/bar/baz',
      '/:foo/bar/:baz',
      '/:foo/:bar/baz',
      '/*/bar/baz',
      '/*/baz/*',
      '/*/baz',
      '/:foo',
      '/:foo/:bar',
      '/:foo/:bar/:baz',
      '/:foo/:bar/*',
      'r|^/foo/\\d+$|',
      '/:foo/*',
      'GET /*',
      '/*'
    ];

    var sortedAddresses = sortRouteAddresses(addresses);

    assert(_.isEqual(sortedAddresses, expected), 'Got unexpected address order: ' + JSON.stringify(sortedAddresses));

  });

});
