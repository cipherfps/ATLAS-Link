# [<img title="skipper-disk - Local disk adapter for Skipper" src="http://i.imgur.com/P6gptnI.png" width="200px" alt="skipper emblem - face of a ship's captain"/>](https://github.com/balderdashy/skipper-disk) Disk Blob Adapter

[![NPM version](https://badge.fury.io/js/skipper-disk.png)](http://badge.fury.io/js/skipper-disk) &nbsp; &nbsp;
[![Build Status](https://travis-ci.org/balderdashy/skipper-disk.svg?branch=master)](https://travis-ci.org/balderdashy/skipper-disk)

Local filesystem adapter for receiving [upstreams](https://github.com/balderdashy/skipper#what-are-upstreams). Particularly useful for streaming multipart file uploads from the [Skipper](github.com/balderdashy/skipper) body parser.


## Installation

```
$ npm install skipper-disk --save
```

This module is part of the default configuration in [Sails](https://sailsjs.com).

> If you're using this module outside of Sails (e.g. Express or a vanilla Node.js server), make sure you have skipper itself [installed as your body parser](https://sailsjs.com/documentation/concepts/middleware?q=adding-or-overriding-http-middleware).



## Usage

> This module is bundled as the default file upload adapter in Skipper, so the following usage is slightly simpler than it is with the other Skipper file upload adapters.

In the route(s) / controller action(s) where you want to accept file uploads, do something like:

```javascript
req.file('avatar')
.upload({
  // ...options here...
},function whenDone(err, uploadedFiles) {
  if (err) return res.negotiate(err);
  else return res.ok({
    files: uploadedFiles,
    textParams: req.params.all()
  });
});
```

For more detailed usage information and a full list of available options, see the Skipper repo, especially the section on "[https://github.com/balderdashy/skipper#uploading-files-to-disk](Uploading to Local Disk)".


## Contribute

Check out the [contribution guide](https://sailsjs.com/contributing) and [roadmap](https://trello.com/b/s9zEnyG7).

To run the tests:

```shell
$ npm test
```




## License

**[MIT](./LICENSE)**

[Mike McNeil](https://sailsjs.com/studio), [Balderdash Design Co.](http://balderdash.co), [Sails Co.](https://sailsjs.com/about)

See `LICENSE.md`.

This module is part of the [Sails framework](https://sailsjs.com), and is free and open-source under the [MIT License](https://sailsjs.com/license).


![image_squidhome@2x.png](http://i.imgur.com/RIvu9.png)

