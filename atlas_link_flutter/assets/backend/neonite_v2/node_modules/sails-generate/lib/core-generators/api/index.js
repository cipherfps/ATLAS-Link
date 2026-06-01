/**
 * sails-generate-api
 *
 * Usage:
 * `sails generate api <resource>`
 *
 * @type {Dictionary}
 */

module.exports = {

  targets: {

    // Call out to both the model and controller generators.
    '.': [
      'model',
      'controller'
    ]

  }

};
