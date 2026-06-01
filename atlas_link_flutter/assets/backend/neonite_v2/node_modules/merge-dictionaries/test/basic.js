var assert = require('assert');
var _ = require('@sailshq/lodash');
var mergeDictionaries = require('../');
// var mergeDictionaries = _.merge;

describe('basic usage', function() {

  it('should do basic merges correctly', function() {

    var dictA = { foo: 'bar', nested: { owl: 'hoot', dog: 'woof' } };
    var dictB = { bleep: 'bloop', nested: { dog: 'arf', cat: 'meow', sounds: ['honk', 'squeak'], dict: {'abc': 123} } };
    var merged = mergeDictionaries(dictA, dictB);

    assert(_.isEqual(merged, { foo: 'bar', bleep: 'bloop', nested: { owl: 'hoot', dog: 'arf', cat: 'meow', sounds: ['honk', 'squeak'], dict: {'abc': 123} } }), 'Result of merge was incorrect.');

  });

  it('should merge non-plain-objects correctly', function() {

    var constr = function() {this.abc = 123; return this;};
    constr.prototype.foo = 'bar';
    var dictA = { abc: new constr() };
    var dictB = { abc: { owl: 'hoot' } };
    var owl = dictB.abc;
    var merged = mergeDictionaries(dictA, dictB);
    assert(_.isEqual(merged.abc, { owl: 'hoot' } ), 'Result of merge was incorrect.');
    assert(owl === merged.abc, '`nonEmpty` should be direct reference to `merged.foo`, but it\'s a different object!');

  });


  it('should maintain object references when merging modules together (empty dict)', function() {

    var dictA = { foo: 'bar', nested: { empty: {} } };
    var dictB = { nested: { empty: {} } };
    var empty = dictB.nested.empty;
    var merged = mergeDictionaries(dictA, dictB);

    assert(_.isEqual(merged, { foo: 'bar', nested: { empty: {} } }), 'Result of merge was incorrect.');
    assert(empty === merged.nested.empty, '`empty` should be direct reference to `merged.nested.empty`, but it\'s a different object!');

  });//</should maintain object references when merging modules together>

  it('should maintain object references when merging modules together (non-empty dict)', function() {

    var dictA = { foo: 'bar' };
    var dictB = { nested: { nonEmpty: { owl: 'hoot' } } };
    var nonEmpty = dictB.nested.nonEmpty;
    var merged = mergeDictionaries(dictA, dictB);

    assert(_.isEqual(merged, { foo: 'bar', nested: { nonEmpty: { owl: 'hoot' } } }), 'Result of merge was incorrect.');
    assert(nonEmpty === merged.nested.nonEmpty, '`nonEmpty` should be direct reference to `merged.nested.nonEmpty`, but it\'s a different object!');

  });//</should maintain object references when merging modules together>

  it('should maintain object references when merging modules together (function w/ keys)', function() {

    var fn = function(){};
    fn.foo = 'bar';
    var dictA = { foo: fn };
    var dictB = { foo: { owl: 'hoot' } };
    var owl = dictB.foo;
    var merged = mergeDictionaries(dictA, dictB);

    assert(_.isEqual(merged, { foo: { owl: 'hoot' } }), 'Result of merge was incorrect.');
    assert(owl === merged.foo, '`nonEmpty` should be direct reference to `merged.foo`, but it\'s a different object!');

  });//</should maintain object references when merging modules together>

  it('should not attempt to merge arrays (it should replace array a with array b)', function() {

    var dictA = { foo: ['owl', 'snake', 'fish'] };
    var dictB = { foo: ['cat', 'dog']};
    var merged = mergeDictionaries(dictA, dictB);

    assert.equal(merged.foo.length, 2);
    assert.equal(merged.foo[0], 'cat');
    assert.equal(merged.foo[1], 'dog');

  });//</should not attempt to merge arrays>

  it('should not attempt to merge an array with a string (it should replace the string with the array)', function() {

    var dictA = { foo: 'abcde' };
    var dictB = { foo: ['cat', 'dog']};
    var merged = mergeDictionaries(dictA, dictB);

    assert.equal(merged.foo.length, 2);
    assert.equal(merged.foo[0], 'cat');
    assert.equal(merged.foo[1], 'dog');

  });//</should not attempt to merge an array with a string>

});
