# <%= packageName %>

Provides easy access to `<%= adapterName %>` from Sails.js & Waterline.

This module is a Sails/Waterline community adapter.  Its goal is to provide a set of declarative interfaces, conventions, and best-practices for integrating with the <%= adapterName %> database/service.

Strict adherence to an adapter specification enables the (re)use of built-in generic test suites, standardized documentation, reasonable expectations around the API for your users, and overall, a more pleasant development experience for everyone.


## Installation

To install this adapter, run:

```sh
$ npm install <%= packageName %>
```

Then [connect the adapter](https://sailsjs.com/documentation/reference/configuration/sails-config-datastores) to one or more of your app's datastores.

## Usage

Visit [Models & ORM](https://sailsjs.com/docs/concepts/models-and-orm) in the docs for more information about using models, datastores, and adapters in your app/microservice.

## Questions?

See [Extending Sails > Adapters > Custom Adapters](https://sailsjs.com/documentation/concepts/extending-sails/adapters/custom-adapters) in the [Sails documentation](https://sailsjs.com/documentation), or check out [recommended support options](https://sailsjs.com/support).

<a href="https://sailsjs.com" target="_blank" title="Node.js framework for building realtime APIs."><img src="https://github-camo.global.ssl.fastly.net/9e49073459ed4e0e2687b80eaf515d87b0da4a6b/687474703a2f2f62616c64657264617368792e6769746875622e696f2f7361696c732f696d616765732f6c6f676f2e706e67" width=60 alt="Sails.js logo (small)"/></a>


## Compatibility

This adapter implements the following methods:

| Method               | Status            | Category      |
|:---------------------|:------------------|:--------------|
| registerDatastore    | _**in progress**_ | LIFECYCLE     |
| teardown             | _**in progress**_ | LIFECYCLE     |
| create               | Planned           | DML           |
| createEach           | Planned           | DML           |
| update               | Planned           | DML           |
| destroy              | Planned           | DML           |
| find                 | Planned           | DQL           |
| join                 | _**???**_         | DQL           |
| count                | Planned           | DQL           |
| sum                  | Planned           | DQL           |
| avg                  | Planned           | DQL           |
| define               | Planned           | DDL           |
| drop                 | Planned           | DDL           |
| setSequence          | _**???**_         | DDL           |


## License

This <%= adapterName %> adapter is available under the **<%= license %> license**.

As for [Waterline](http://waterlinejs.org) and the [Sails framework](https://sailsjs.com)?  They're free and open-source under the [MIT License](https://sailsjs.com/license).


![image_squidhome@2x.png](http://i.imgur.com/RIvu9.png)
