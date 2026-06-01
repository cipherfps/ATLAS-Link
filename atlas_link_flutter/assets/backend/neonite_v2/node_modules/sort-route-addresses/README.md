# An algorithm for ordering route addresses

### Definition of a "route address"

For the purposes of this algorithm, a route address is a string containing:

* An optional HTTP verb (or `ALL`) prefix, followed by a space, followed by:
* 1 or more path components, where each path component is:
  * A forward slash `/`, followed by:
  * A colon `:` followed by any combination of letters and numbers (a "param"), OR
  * A star `*` (a "wildcard"), OR 
  * Any combination of letters and numbers (a "static path component")

In other words, any Sails-compatible route path.

### Algorithm

Given an unordered list of route addresses:

1. Find the maximum number of parts (`maxParts`) in any address, by ignoring the optional verb prefix and initial forward slash and splitting each address on the remaining `/` characters.
2. For each address, construct a string (`rank`) by examining each part in the address from left to right and:
   * Adding a `1` to the string for each static path component
   * Adding a `2` to the string for each param component
   * Adding a `3` to the string for each wildcard component
   * If the address being examined has fewer than `maxParts` parts, pad the string with `0`s if no wildcards were encountered, or `4`s if wildcards were encountered.
   * Add a `0` to the end of the string if the address has a specific verb prefix (i.e. not `ALL`), and a `1` if it has a `ALL` prefix or no prefix.
   * Finally, prefix a `5` at the beginning of the string if the path has _no_ static components<sup>[1](#footnote1)</sup>.

3. Sort the addresses by their `rank`, with lesser ranks coming before greater ones.

### Example

```
RANK  ADDRESS
----  -----
1000  GET /foo
1001  /foo
1101  /foo/bar
1111  /foo/bar/baz
1120  GET /foo/bar/:baz
1121  /foo/bar/:baz
1130  GET /foo/bar/*
1131  /foo/bar/*
1201  /foo/:bar
1211  /foo/:bar/baz
1221  /foo/:bar/:baz
1311  /foo/*/baz
1341  /foo/*
2101  /:foo/bar
2111  /:foo/bar/baz
2121  /:foo/bar/:baz
2211  /:foo/:bar/baz
3111  /*/bar/baz
3131  /*/baz/*
3141  /*/baz
52001 /:foo
52201 /:foo/:bar
52221 /:foo/:bar/:baz
52231 /:foo/:bar/*
52341 /:foo/*
53440 GET /*
53441 /*
```

<hr/>

<a name="footnote1"><sup>1</sup></a>: This ensures that addresses like `/*/baz/*` are ranked above ones like `/:foo/:bar/:baz` -- the static `baz` component implies that the author intends for `*/baz/*` to handle request URLs of at least three components, one of which is `baz`; if `/:foo/:bar/:baz/` were ranked higher in the list, it would swallow the subset of those URLs with _exactly_ three components.


## Help

If you have a question, need professional support, or just want to talk Sails/Node.js with other folks in the community, click [here](https://sailsjs.com/support).


## Bugs &nbsp; [![NPM version](https://badge.fury.io/js/sort-route-addresses.svg)](http://npmjs.com/package/sort-route-addresses)

To report a bug, [click here](https://sailsjs.com/bugs).


## Contributing

Please observe the guidelines and conventions laid out in the [Sails project contribution guide](https://sailsjs.com/documentation/contributing) when opening issues or submitting pull requests.

[![NPM](https://nodei.co/npm/sort-route-addresses.png?downloads=true)](http://npmjs.com/package/sort-route-addresses)

## License

Like the [Sails framework](https://sailsjs.com), this package is free and open-source under the [MIT License](https://sailsjs.com/license).
