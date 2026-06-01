var assert = require('assert');
var should = require('should');
var _ = require('@sailshq/lodash');
_.mergeDefaults = require('../');



describe('4-level-deep merge', function() {

  var X = {
    baz: {
      foo: {
        a: 1,
        b: 2,
        bar: {
          a: 1,
          b: 2
        }
      }
    }
  };
  var Y = {
    foon: 82,
    baz: {
      foo: {
        a: 100,
        c: 3,
        bar: {
          a: 10,
          c: 3
        }
      }
    }
  };
  var result = _.mergeDefaults(X, Y);

  it('should retain the values in X (first arg)', function() {
    assert.equal(X.baz.foo.a, 1);
    assert.equal(X.baz.foo.bar.a, 1);
    assert.equal(X.baz.foo.bar.b, 2);
  });

  it('should receive new values from Y (second arg)', function() {
    assert.equal(X.baz.foo.bar.c, 3);
    assert.equal(X.foon, 82);
  });
});