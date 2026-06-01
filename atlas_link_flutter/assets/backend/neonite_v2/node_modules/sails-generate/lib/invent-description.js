/**
 * Module dependencies
 */

var _ = require('@sailshq/lodash');


/**
 * Given the identifier for an action/helper/etc, invent an appropriate description.
 * (i.e. <140 characters, in the imperative mood, sentence case, and so on)
 *
 * @param  {String} identifier
 * @param  {Boolean?} isForAction  (whether this is for an action)
 * @returns {String}
 */
module.exports = function inventDescription (identifier, isForAction){

  // Support slashes or dots:
  identifier = identifier.replace(/\/+/g, '.');

  // FOR REFERENCE:
  //
  // GENERIC
  //  · user/create            => Create user.
  //  · signup                 => Signup something.
  //  · user/signup            => Signup user.
  //  · channel/ban-all-users  => Ban all users.
  //  · channel/destroy-all    => Destroy all.
  //  · channel/destroy        => Destroy channel.
  //  · foo/bar/stock/sell     => Sell stock.
  //  · foo/bar/stock/sell-all => Sell all.
  //
  // FOR ACTIONS ONLY
  //  · orders/download-disclosure-pdf  => Download disclosure pdf file (returning a stream).
  //  · webhooks/receive-from-slack     => Receive webhook requests/auth redirects from Slack.
  //
  var chunks = identifier.split('.');
  var stem = _.last(chunks);
  var verbWord = _.words(stem)[0];
  if (isForAction && verbWord.toLowerCase() === 'download') {
    // - FUTURE: add special success exit with proper outputType, etc
    // - FUTURE: add `var downloading;` and `return downloading;` in generated
    // code, with a comment explaining that it's the Readable stream you want
    // to automatically pipe to the response.
    // - FUTURE: add commented-out example code of `this.res.type('application/pdf');`
    return 'Download '+(_.map(_.words(stem).slice(1), function(word){ return word[0].toLowerCase() + word.slice(1); }).join(' '))+' file (returning a stream).';
  }
  else if (isForAction && verbWord.toLowerCase() === 'receive' && (_.words(stem)[1] && _.words(stem)[1].toLowerCase() === 'from')) {
    // - FUTURE: add comment in generated `inputs` clarifying that the parameters
    // to expect are determined by the 3rd party system that makes this webhook
    // request or auth redirect, and thus should be set up accordingly.
    // - FUTURE: add special success exit with note about how some APIs behave
    // with webhooks that return non-2xx status codes, and to check the
    // documentation for whatever you're integrating with to be sure you know
    // how it behaves.
    return 'Receive webhook requests and/or incoming auth redirects from'+(
      (_.words(stem)[2])?
      ( ' '+_.capitalize(_.words(stem)[2])+'.' )
      : '…'
    );
  }
  else if (_.words(stem).length === 1 && chunks.length === 1) {
    return _.capitalize(verbWord) + ' something.';
  }
  else if (_.words(stem).length === 1 && chunks.length > 1) {
    var lastChunkBeforeStem = chunks.slice(-2, -1)[0];
    var akkusativ = _.words(lastChunkBeforeStem);
    var midSentenceCaseAkkusativ = _.map(_.words(akkusativ), function (word){ return word[0].toLowerCase() + word.slice(1); }).join(' ');
    return _.capitalize(verbWord)+' '+midSentenceCaseAkkusativ+'.';
  }
  else {
    // We could go with `inferredDescription = sentenceCaseStem+'.'`, but it's not worth it
    // since that's just identical to the sentence-case stem pretty much.  So instead, we
    // leave this as empty string so that it can be handled on a case-by-case basis.
    return '';
  }

};
