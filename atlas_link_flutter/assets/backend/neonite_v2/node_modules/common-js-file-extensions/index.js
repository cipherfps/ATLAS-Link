/**
 * This module documents a lost of the most common used javascript extensions\
 * used by different transpilers.
 *
 * This list is being used by Sails to filter out extensions that should be
 * read by the module loader
 *
 * Copyright 2016 (c) Luis Lobo Borobia <luislobo@gmail.com>
 *
 * Based on the input from Mike McNeil
 *
 * License MIT
 */

var codeExtensions = [
  'js', // built-in
  'iced', // http://maxtaco.github.io/coffee-script/
  'liticed', // http://maxtaco.github.io/coffee-script/ (literate iced)
  'iced.md', // http://maxtaco.github.io/coffee-script/ (literate iced)
  'coffee', // http://coffeescript.org/
  'litcoffee', // http://coffeescript.org/ (literate coffee)
  'coffee.md', // http://coffeescript.org/ (literate coffee)
  'ts', // https://www.typescriptlang.org/
  'cs',  // http://bridge.net/ ??
  'ls', // http://livescript.net/
  'es6', // https://babeljs.io
  'es', // https://babeljs.io
  'jsx', // https://babeljs.io https://facebook.github.io/jsx/.
  'sjs', // http://onilabs.com/stratifiedjs
  'co', // http://satyr.github.io/coco/
  'eg' // http://www.earl-grey.io/
];

var configExtensions = [
  'json', // built-in
  'json.ls', // http://livescript.net/
  'json5' // http://json5.org/
];

module.exports = {
  code: codeExtensions,
  config: configExtensions
};
