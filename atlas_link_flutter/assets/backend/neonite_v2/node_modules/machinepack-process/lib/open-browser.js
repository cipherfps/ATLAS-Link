module.exports = {


  friendlyName: 'Open browser',


  description: 'Open the user\'s browser and navigate to the given URL.',


  sync: true,


  inputs: {

    url: {
      example: 'http://google.com',
      required: true
    }

  },


  fn: function (inputs, exits){

    var openBrowserAndNavigateToUrl = require('opn');

    // Attempt to open the given URL in a browser window.
    openBrowserAndNavigateToUrl(inputs.url);

    return exits.success();
  }


};
