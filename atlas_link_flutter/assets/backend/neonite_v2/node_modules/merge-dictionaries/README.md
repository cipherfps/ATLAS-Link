# merge-dictionaries

A wrapper around the Lodash 3 `.merge()` function that addresses some issues with arrays and object references.  Intended for merging configuration files together.

### Usage

```
npm install merge-dictionaries
```

```
var mergeDictionaries = require('merge-dictionaries');
mergeDictionaries(dictA, dictB);
```

### What&rsquo;s the problem that this solves?

The `.merge()` function works great in most cases, but the default behavior has two problems:

First, array values in the second argument are merged weirdly with values in the first argument.  Examples:

```
// Two arrays are "merged" together by replacing values in the first array with values from
// the second, by index:
var dictA = { foo: ['owl', 'snake', 'fish'] };
var dictB = { foo: ['cat', 'dog']};
_.merge(dictA, dictB);

// Results in:
// { foo: ['cat', 'dog', 'fish'] }


// Merging an array into a string causes the string to be busted up into an array of characters,
// which is then merged on-top-of as above:
var dictA = { foo: 'abcde' };
var dictB = { foo: ['cat', 'dog']};
_.merge(dictA, dictB);

// Results in:
// { foo: ['cat', 'dog', 'c', 'd', 'e'] }
```

Second, dictionaries in the second argument that do not have corresponding dictionary values in the first argument (or whose corresponding values are `{}`) are copied over by _value_ instead of by _reference_:

```
var dictA = { foo: 'bar' };
var dictB = { nested: { owl: 'hoot' } };
var owl = dictB.nested; // <-- owl is { owl: 'hoot' }
var merged = _.merge(dictA, dictB);

// Results in:
// { foo: 'bar', nested: { owl: 'hoot' } }

console.log(owl === merged.nested);
// Results in:
// false
```

This might not seem like a big issue, but it can be a real problem when merging dictionaries that contain references to objects created by another module.  For example imagine:

```
var configA = { someConfigValue: 'some default value' };
var configB = { someConfigValue: 'a custom value',  someModule: require('my-module') };
var mergedObj = _.merge(configA, configB);
```

where `my-module` looks like:

```
module.exports = ( function() {
  // Declare the public data dictionary exposed by this module.
  var publicData = {};
  return {
    // Expose the public data to the outside world.
    somePublicData: publicData
    // Declare a function for initializing the module.
    init: function() {
      publicData.foo = 'bar';
    }
  }
} )()
```

If you call `mergedObj.someModule.init()` later, you might expect `mergedObj.someModule.somePublicData` to be set to `{foo: 'bar'}`, but it&rsquo;ll still just be an empty dictionary, because a _different `somePublicData` dictionary_ was copied into the merged object.

### What&rsquo;s the solution?

The solution is very simple, because the `_.merge()` function can take a third argument that allows you to customize the merge behavior.  We can use this to tell `_.merge()` to _only_ do its regular thing when the left-hand value is a non-empty plain dictionary.  In all other cases, `a` is replaced by `b`.

> Keep in mind that this means that if `a` _looks_ like a dictionary, but was created by a custom constructor (i.e. it is not a &ldquo;plain&rdquo; dictionary, it will be replaced by `b`!  For example:
>
> ```
> var myClass = function() {this.foo = 'bar'};
> var obj1 = { abc: new myClass() };
> // Result:
> // { abc: { foo: 'bar' } }
>
> var obj2 = { abc: { owl: 'hoot' } };
> var merged = mergeDictionaries(obj1, obj2);
>
> // Result:
> // { abc: { owl: 'hoot' } }
> ```


## Help

If you have questions or are having trouble, click [here](http://sailsjs.com/support).


## Bugs &nbsp; [![NPM version](https://badge.fury.io/js/merge-dictionaries.svg)](http://npmjs.com/package/merge-dictionaries)

To report a bug, [click here](http://sailsjs.com/bugs).


## Contributing

Please observe the guidelines and conventions laid out in the [Sails project contribution guide](http://sailsjs.com/documentation/contributing) when opening issues or submitting pull requests.

[![NPM](https://nodei.co/npm/merge-dictionaries.png?downloads=true)](http://npmjs.com/package/merge-dictionaries)

## License

Like the [Sails framework](http://sailsjs.com), this package is free and open-source under the [MIT License](http://sailsjs.com/license).
