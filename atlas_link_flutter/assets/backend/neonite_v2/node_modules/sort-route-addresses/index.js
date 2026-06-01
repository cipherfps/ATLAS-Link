/**
 * Module dependencies.
 */
var _ = require('@sailshq/lodash');

module.exports = function sortRouteAddresses (addresses, options) {

  // Ensure options is an object.
  options = options || {};

  // Regular expression to test whether an address corresponds to a
  // Sails regex route.
  var regExRoute = /^r\|(.*)\|(.*)$/;

  // First, find the # of components in the longest route path.
  var maxComponents = _.reduce(addresses, function(memo, address) {

    // Parse the path out of the address.
    var addressInfo = parseAddress(address);
    var path = addressInfo.path;

    // If the path is a Sails regex, skip it (unless we're instructed not to)
    if (path.match(regExRoute) && !options.sortRegexes) {
      return memo;
    }

    // Split the path into components.
    var components = path.split('/');

    // The first part should be blank (since routes should start with /),
    // but gracefully handle the case of routes not starting with /
    if (components[0] === '') {
      components.shift();
    }

    // If this path has more components than the max we've encountered so far,
    // make it the new max.
    if (components.length > memo) {memo = components.length;}

    return memo;

  }, 0);

  // Declare a var to hold the last rank produced
  // (used for sorting regex addresses)
  var lastRank = Array(maxComponents).fill(0).join('');

  // Now create a dictionary mapping ranks to addresses.
  var rankedAddresses = _.reduce(addresses, function(memo, address) {

    // Get the verb and path from the address.
    var addressInfo = parseAddress(address);
    var path = addressInfo.path;
    var verb = addressInfo.verb;

    // If the path represents a Sails regex address, and we're not told
    // explicitly to sort it, just give it the same rank as the whatever
    // address we saw last.  This means it'll be placed directly after
    // whichever address it was following in the unsorted address list.
    if (path.match(regExRoute) && !options.sortRegexes) {
      rank = lastRank;
      memo[rank] = memo[rank] || [];
      memo[rank].push(address);
      return memo;
    }

    // Declare a flag indicating whether a (non-"all") verb was specified.
    var hasVerb = (verb && verb !== 'all');

    // Split the path int components.
    var components = path.split('/');

    // The first component should be blank (since routes should start with /),
    // but gracefully handle the case of routes not starting with /
    if (components[0] === '') {
      components.shift();
    }

    // Declare a flag indicating whether the path contains a wildcard component.
    var seenWildcard = false;

    // Declare a flag indicating whether the path contains a static component.
    var seenStatic = false;

    // Declare a string to hold the route address rank as we build it.
    var rank = '';

    // Iterate from 0 to maxComponents, examining this particular address's component
    // at each index (if any) and assigning it a value.
    for (var i = 0; i < maxComponents; i++) {

      // If the current route address has a component at the current index (i.e. it has
      // at least `i+1` components)...
      if (components[i]) {
        // Add a '3' for each wildcard.
        if (components[i] === '*' || components[i] === '?*') {
          rank += '3';
          // Indicate that this address has a wildcard.
          seenWildcard = true;
        }
        // Add a `2` for each param.
        else if (components[i][0] === ':') {
          rank += '2';
        }
        // Add a `1` for each static path component.
        else {
          rank += '1';
          // Indicate that this address has a static component.
          seenStatic = true;
        }
      }
      // If the current route address does NOT have a component at the current index
      // (i.e. it has fewer than `i+1` components)...
      else {
        // Add a `4` to pad out spaces if the address has any wildcards.
        if (seenWildcard) {
          rank += '4';
        }
        // Add a `0` to pad out spaces if no wildcard has been seen.
        else {
          rank += '0';
        }
      }
    }

    // Add a final 0 or 1 to ensure that routes with no verb come after
    // ranks with a verb specified.
    if (hasVerb) {
      rank += '0';
    }
    else {
      rank += '1';
    }

    // Add a `5` to the beginning of the rank if the address has _no_ static
    // components, to ensure that _all_ routes with at least one static component
    // is bound before _any_ route without one.
    if (!seenStatic) {
      rank = '5' + rank;
    }

    // More than one address may end up with the same rank, so we'll map each
    // rank to an _array_ of addresses.
    memo[rank] = memo[rank] || [];
    memo[rank].push(address);

    // Update `lastRank`.
    lastRank = rank;

    return memo;

  }, {});

  // If we are being asked to just return the ranked addresses, do so now.
  if (options.returnRanked) {
    return rankedAddresses;
  }

  // Sort the ranks.
  var sortedRanks = _.keys(rankedAddresses).sort();

  // Get the final sorted list of addresses.
  var sortedAddresses = _.reduce(sortedRanks, function(memo, rank) {
    memo = memo.concat(rankedAddresses[rank]);
    return memo;

  }, []);

  // Return the final sorted list.
  return sortedAddresses;

};

function parseAddress(address) {
  var path = address.toLowerCase();
  var verbExpr = /^(all|get|post|put|delete|trace|options|connect|patch|head)\s+/i;
  var verbSpecified = _.last(address.match(verbExpr) || []) || '';
  verbSpecified = verbSpecified.toLowerCase();

  // If a verb was specified, eliminate the verb from the original string
  if (verbSpecified) {
    path = path.replace(verbExpr, '');
  }

  return {
    verb: verbSpecified,
    path: path
  };

}
