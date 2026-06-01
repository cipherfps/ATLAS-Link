/**
 * Module dependencies
 */

var path = require('path');
var crypto = require('crypto');


/**
 * sails-generate-new
 *
 * Usage:
 * `sails new foo`
 *
 * @type {Dictionary}
 */

module.exports = {

  templatesDirectory: path.resolve(__dirname,'./templates'),

  // scopeExample: {
  //   // Required:
  //   args: ['my-new-app'],
  //   rootPath: '/Users/mikermcneil/code',
  //   sailsRoot: '/usr/local/lib/node_modules/sails',
  //
  //   // Automatic (but can be manually overridden:)
  //   appName: 'my-new-app',
  //   templatesDirectory: '/usr/local/lib/node_modules/sails/node_modules/sails-generate/node_modules/sails-generate-new/templates',
  // },

  before: require('./before'),

  after: require('./after'),

  targets: {

    '.': [
      //   ██████╗ ██████╗ ██╗   ██╗███╗   ██╗████████╗███████╗██╗██╗     ███████╗
      //  ██╔════╝ ██╔══██╗██║   ██║████╗  ██║╚══██╔══╝██╔════╝██║██║     ██╔════╝
      //  ██║  ███╗██████╔╝██║   ██║██╔██╗ ██║   ██║   █████╗  ██║██║     █████╗
      //  ██║   ██║██╔══██╗██║   ██║██║╚██╗██║   ██║   ██╔══╝  ██║██║     ██╔══╝
      //  ╚██████╔╝██║  ██║╚██████╔╝██║ ╚████║   ██║   ██║     ██║███████╗███████╗
      //   ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚═╝     ╚═╝╚══════╝╚══════╝
      //
      {
        overridable: 'gruntfile',
        generator: {
          targets: {
            './Gruntfile.js': { template: 'Gruntfile.js.template' },
            './tasks': { folder: {} },
            './tasks/config': { folder: {} },
            './tasks/register': { folder: {} },
          }
        }
      },//</gruntfile>
      //  ██████╗  █████╗  ██████╗██╗  ██╗███████╗███╗   ██╗██████╗
      //  ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔════╝████╗  ██║██╔══██╗
      //  ██████╔╝███████║██║     █████╔╝ █████╗  ██╔██╗ ██║██║  ██║
      //  ██╔══██╗██╔══██║██║     ██╔═██╗ ██╔══╝  ██║╚██╗██║██║  ██║
      //  ██████╔╝██║  ██║╚██████╗██║  ██╗███████╗██║ ╚████║██████╔╝
      //  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝
      //
      {
        overridable: 'backend',
        generator: {
          before: function(scope, cb) {

            //  ┌┐ ┌─┐┬┌─┌─┐  ┌─┐  ┬─┐┌─┐┌┐┌┌┬┐┌─┐┌┬┐  ┌┬┐┌─┐┌┬┐┌─┐  ┌─┐┌┐┌┌─┐┬─┐┬ ┬┌─┐┌┬┐┬┌─┐┌┐┌  ┬┌─┌─┐┬ ┬
            //  ├┴┐├─┤├┴┐├┤   ├─┤  ├┬┘├─┤│││ │││ ││││   ││├─┤ │ ├─┤  ├┤ ││││  ├┬┘└┬┘├─┘ │ ││ ││││  ├┴┐├┤ └┬┘
            //  └─┘┴ ┴┴ ┴└─┘  ┴ ┴  ┴└─┴ ┴┘└┘─┴┘└─┘┴ ┴  ─┴┘┴ ┴ ┴ ┴ ┴  └─┘┘└┘└─┘┴└─ ┴ ┴   ┴ ┴└─┘┘└┘  ┴ ┴└─┘ ┴
            //  ┌─    ┌─┐┌─┐┬─┐  ╔╦╗╔═╗╔╦╗╔═╗╦  ╔═╗  ╦╔═╗    ─┐
            //  │───  ├┤ │ │├┬┘  ║║║║ ║ ║║║╣ ║  ╚═╗  ║╚═╗  ───│
            //  └─    └  └─┘┴└─  ╩ ╩╚═╝═╩╝╚═╝╩═╝╚═╝o╚╝╚═╝    ─┘
            // Now bake up a data encryption key to inject into our `config/models.js` file.
            // > e.g. 'DPjGWuGIfZuUPmSEuMtyXoO0zN9UG52vU1zoV0F2X1k='

            // Generate a cryptographically random 32 byte key string to use as this new app's
            // default DEK during development.
            scope.defaultDEK = crypto.randomBytes(32).toString('base64');


            //  ┌┐ ┌─┐┬┌─┌─┐  ┌─┐  ┬─┐┌─┐┌┐┌┌┬┐┌─┐┌┬┐  ┌─┐┌─┐┌─┐┌─┐┬┌─┐┌┐┌  ┌─┐┌─┐┌─┐┬─┐┌─┐┌┬┐
            //  ├┴┐├─┤├┴┐├┤   ├─┤  ├┬┘├─┤│││ │││ ││││  └─┐├┤ └─┐└─┐││ ││││  └─┐├┤ │  ├┬┘├┤  │
            //  └─┘┴ ┴┴ ┴└─┘  ┴ ┴  ┴└─┴ ┴┘└┘─┴┘└─┘┴ ┴  └─┘└─┘└─┘└─┘┴└─┘┘└┘  └─┘└─┘└─┘┴└─└─┘ ┴
            //  ┌─    ┌─┐┌─┐┬─┐  ╔═╗╔═╗╔═╗╔═╗╦╔═╗╔╗╔  ╦╔═╗    ─┐
            //  │───  ├┤ │ │├┬┘  ╚═╗║╣ ╚═╗╚═╗║║ ║║║║  ║╚═╗  ───│
            //  └─    └  └─┘┴└─  ╚═╝╚═╝╚═╝╚═╝╩╚═╝╝╚╝o╚╝╚═╝    ─┘
            // Now bake up a session secret to inject into our `config/session.js` file.

            // Combine random and case-specific factors into a base string
            // (creation date, random number, and Node.js version string)
            var baseStringToHash = '';
            baseStringToHash += Date.now();
            baseStringToHash += crypto.randomBytes(64).toString('hex');
            baseStringToHash += process.version;

            // Now cook up some hash using the base string.
            // > This will be used as the session secret we inject into the `config/session.js` file.
            scope.secret = crypto.createHash('md5').update(baseStringToHash).digest('hex');

            // Continue onwards to generate all those exciting files.
            return cb();
          },
          targets: {

            //  ██╗   ██╗██╗███████╗██╗    ██╗███████╗
            //  ██║   ██║██║██╔════╝██║    ██║██╔════╝
            //  ██║   ██║██║█████╗  ██║ █╗ ██║███████╗
            //  ╚██╗ ██╔╝██║██╔══╝  ██║███╗██║╚════██║
            //   ╚████╔╝ ██║███████╗╚███╔███╔╝███████║
            //    ╚═══╝  ╚═╝╚══════╝ ╚══╝╚══╝ ╚══════╝
            //
            // Call out to `sails-generate-views`.
            '.': [
              {
                overridable: 'views',
                generator: {
                  targets: {
                    './views/.eslintrc': { copy: 'views/eslintrc-override-for-inline-script-tags.template' },

                    './views/498.ejs': { onlyIf: 'caviar', copy: 'views/498.ejs' },
                    './views/404.ejs': { copy: 'views/404.ejs', overridable: '404' },
                    './views/500.ejs': { copy: 'views/500.ejs', overridable: '500' },
                    './views/layouts': { folder: {} },
                    './views/layouts/layout.ejs': { copy: 'views/traditional-layout.ejs',  overridable: 'layout' },
                    './views/layouts/layout-email.ejs': { onlyIf: 'caviar', copy: 'views/layout-email.ejs',  overridable: 'layout-email' },

                    './views/emails':                              { onlyIf: 'caviar', folder: {} },
                    './views/emails/internal': { onlyIf: 'caviar', folder: {} },
                    './views/emails/internal/email-contact-form.ejs': { onlyIf: 'caviar', copy: 'views/emails/internal/email-contact-form.ejs' },
                    './views/emails/email-reset-password.ejs': { onlyIf: 'caviar', copy: 'views/emails/email-reset-password.ejs' },
                    './views/emails/email-verify-account.ejs': { onlyIf: 'caviar', copy: 'views/emails/email-verify-account.ejs' },
                    './views/emails/email-verify-new-email.ejs': { onlyIf: 'caviar', copy: 'views/emails/email-verify-new-email.ejs' },
                    './views/pages': { folder: {} },
                    './views/pages/homepage.ejs': { copy: 'views/homepage.ejs', overridable: 'homepage' },
                    './views/pages/account': { onlyIf: 'caviar', folder: {} },
                    './views/pages/account/edit-password.ejs': { onlyIf: 'caviar', copy: 'views/pages/account/edit-password.ejs' },
                    './views/pages/account/account-overview.ejs': { onlyIf: 'caviar', copy: 'views/pages/account/account-overview.ejs' },
                    './views/pages/account/edit-profile.ejs': { onlyIf: 'caviar', copy: 'views/pages/account/edit-profile.ejs' },
                    './views/pages/contact.ejs': { onlyIf: 'caviar', copy: 'views/pages/contact.ejs' },
                    './views/pages/dashboard': { onlyIf: 'caviar', folder: {} },
                    './views/pages/dashboard/welcome.ejs': { onlyIf: 'caviar', copy: 'views/pages/dashboard/welcome.ejs' },
                    './views/pages/entrance': { onlyIf: 'caviar', folder: {} },
                    './views/pages/entrance/confirmed-email.ejs': { onlyIf: 'caviar', copy: 'views/pages/entrance/confirmed-email.ejs' },
                    './views/pages/entrance/forgot-password.ejs': { onlyIf: 'caviar', copy: 'views/pages/entrance/forgot-password.ejs' },
                    './views/pages/entrance/login.ejs': { onlyIf: 'caviar', copy: 'views/pages/entrance/login.ejs' },
                    './views/pages/entrance/new-password.ejs': { onlyIf: 'caviar', copy: 'views/pages/entrance/new-password.ejs' },
                    './views/pages/entrance/signup.ejs': { onlyIf: 'caviar', copy: 'views/pages/entrance/signup.ejs' },
                    './views/pages/faq.ejs': { onlyIf: 'caviar', copy: 'views/pages/faq.ejs' },
                    './views/pages/legal': { onlyIf: 'caviar', folder: {} },
                    './views/pages/legal/privacy.ejs': { onlyIf: 'caviar', copy: 'views/pages/legal/privacy.ejs' },
                    './views/pages/legal/terms.ejs': { onlyIf: 'caviar', copy: 'views/pages/legal/terms.ejs' },

                  }//</targets>
                }
              }//</views>
            ],


            // /api
            './api/controllers':          { folder: {} },
            './api/controllers/.gitkeep': { onlyIf: 'traditional', copy: '../../../shared-templates/gitkeep.template' },

            './api/controllers/view-faq.js':  { onlyIf: 'caviar', copy: 'api/controllers/view-faq.js' },
            './api/controllers/view-contact.js':  { onlyIf: 'caviar', copy: 'api/controllers/view-contact.js.template' },

            './api/controllers/observe-my-session.js':  { onlyIf: 'caviar', copy: 'api/controllers/observe-my-session.js' },

            './api/controllers/account':  { onlyIf: 'caviar', folder: {} },
            './api/controllers/account/logout.js':  { onlyIf: 'caviar', copy: 'api/controllers/account/logout.js.template' },
            './api/controllers/account/update-billing-card.js':  { onlyIf: 'caviar', copy: 'api/controllers/account/update-billing-card.js.template' },
            './api/controllers/account/update-password.js':  { onlyIf: 'caviar', copy: 'api/controllers/account/update-password.js.template' },
            './api/controllers/account/update-profile.js':  { onlyIf: 'caviar', copy: 'api/controllers/account/update-profile.js.template' },
            './api/controllers/account/view-edit-password.js':  { onlyIf: 'caviar', copy: 'api/controllers/account/view-edit-password.js.template' },
            './api/controllers/account/view-account-overview.js':  { onlyIf: 'caviar', copy: 'api/controllers/account/view-account-overview.js.template' },
            './api/controllers/account/view-edit-profile.js':  { onlyIf: 'caviar', copy: 'api/controllers/account/view-edit-profile.js.template' },

            './api/controllers/dashboard':  { onlyIf: 'caviar', folder: {} },
            './api/controllers/dashboard/view-welcome.js':  { onlyIf: 'caviar', copy: 'api/controllers/dashboard/view-welcome.js' },

            './api/controllers/entrance':  { onlyIf: 'caviar', folder: {} },
            './api/controllers/entrance/confirm-email.js':  { onlyIf: 'caviar', copy: 'api/controllers/entrance/confirm-email.js.template' },
            './api/controllers/entrance/login.js':  { onlyIf: 'caviar', copy: 'api/controllers/entrance/login.js.template' },
            './api/controllers/entrance/send-password-recovery-email.js':  { onlyIf: 'caviar', copy: 'api/controllers/entrance/send-password-recovery-email.js.template' },
            './api/controllers/entrance/signup.js':  { onlyIf: 'caviar', template: 'api/controllers/entrance/signup.js.template' },
            './api/controllers/entrance/update-password-and-login.js':  { onlyIf: 'caviar', copy: 'api/controllers/entrance/update-password-and-login.js.template' },
            './api/controllers/entrance/view-confirmed-email.js':  { onlyIf: 'caviar', copy: 'api/controllers/entrance/view-confirmed-email.js.template' },
            './api/controllers/entrance/view-forgot-password.js':  { onlyIf: 'caviar', copy: 'api/controllers/entrance/view-forgot-password.js.template' },
            './api/controllers/entrance/view-login.js':  { onlyIf: 'caviar', copy: 'api/controllers/entrance/view-login.js.template' },
            './api/controllers/entrance/view-new-password.js':  { onlyIf: 'caviar', copy: 'api/controllers/entrance/view-new-password.js.template' },
            './api/controllers/entrance/view-signup.js':  { onlyIf: 'caviar', copy: 'api/controllers/entrance/view-signup.js.template' },

            './api/controllers/legal/view-privacy.js':  { onlyIf: 'caviar', copy: 'api/controllers/legal/view-privacy.js' },
            './api/controllers/legal/view-terms.js':  { onlyIf: 'caviar', copy: 'api/controllers/legal/view-terms.js' },

            './api/controllers/deliver-contact-form-message.js':  { onlyIf: 'caviar', copy: 'api/controllers/deliver-contact-form-message.js.template' },
            './api/controllers/view-homepage-or-redirect.js':  { onlyIf: 'caviar', copy: 'api/controllers/view-homepage-or-redirect.js.template' },

            './api/models':               { folder: {}, overridable: 'api/models' },
            './api/models/.gitkeep':      { onlyIf: 'traditional', copy: '../../../shared-templates/gitkeep.template', overridable: 'api/models/.gitkeep' },
            './api/models/User.js':       { onlyIf: 'caviar', copy: 'api/models/User.js.template' },

            './api/helpers':              { folder: {} },
            './api/helpers/.gitkeep':     { onlyIf: 'traditional', copy: '../../../shared-templates/gitkeep.template' },
            './api/helpers/send-template-email.js': { onlyIf: 'caviar', copy: 'api/helpers/send-template-email.js.template' },
            './api/helpers/redact-user.js': { onlyIf: 'caviar', copy: 'api/helpers/redact-user.js.template' },
            './api/helpers/broadcast-session-change.js': { onlyIf: 'caviar', copy: 'api/helpers/broadcast-session-change.js.template' },

            './api/responses':                 { onlyIf: 'caviar', folder: {} },
            './api/responses/unauthorized.js': { onlyIf: 'caviar', copy: 'api/responses/unauthorized.js' },
            './api/responses/expired.js':      { onlyIf: 'caviar', copy: 'api/responses/expired.js' },

            './api/policies':                   { folder: {}, overridable: 'api/policies' },
            './api/policies/.gitkeep':          { onlyIf: 'traditional', copy: '../../../shared-templates/gitkeep.template', overridable: 'api/policies' },
            './api/policies/is-logged-in.js':   { onlyIf: 'caviar', copy: 'api/policies/is-logged-in.js', overridable: 'api/policies/is-logged-in.js' },
            './api/policies/is-super-admin.js': { onlyIf: 'caviar', copy: 'api/policies/is-super-admin.js', overridable: 'api/policies/is-super-admin.js' },

            './api/hooks':                  { onlyIf: 'caviar', folder: {} },
            './api/hooks/custom':           { onlyIf: 'caviar', folder: {} },
            './api/hooks/custom/index.js':  { onlyIf: 'caviar', copy: 'api/hooks/custom/index.js.template' },

            // /config
            './config': { folder: {} },
            './config/blueprints.js': { template: 'config/blueprints.js', overridable: 'config/blueprints.js' },
            './config/bootstrap.js': { template: 'config/bootstrap.js.template' },
            './config/datastores.js': { copy: 'config/datastores.js', overridable: 'config/datastores.js' },
            './config/globals.js': { template: 'config/globals.js.template' },
            './config/http.js': { copy: 'config/http.js' },
            './config/i18n.js': { copy: 'config/i18n.js', overridable: 'config/i18n.js' },
            './config/log.js': { copy: 'config/log.js' },
            './config/models.js': { template: 'config/models.js.template', overridable: 'config/models.js' },
            './config/policies.js': { template: 'config/policies.js.template', overridable: 'config/policies.js' },
            './config/routes.js': { template: 'config/routes.js.template' },
            './config/security.js': { template: 'config/security.js.template', overridable: 'config/security.js' },
            './config/session.js': { template: 'config/session.js', overridable: 'config/session.js' },
            './config/sockets.js': { copy: 'config/sockets.js', overridable: 'config/sockets.js' },
            './config/views.js': { template: 'config/views.js', overridable: 'config/views.js' },

            './config/custom.js': { template: 'config/custom.js.template' },
            './config/local.js': { copy: 'config/local.js' },
            './config/env/production.js': { template: 'config/env/production.js.template' },
            './config/env/staging.js': { onlyIf: 'caviar', template: 'config/env/staging.js.template' },

            './config/locales/de.json': { copy: 'config/locales/de.json', overridable: 'config/locales/de.json' },
            './config/locales/en.json': { copy: 'config/locales/en.json', overridable: 'config/locales/en.json' },
            './config/locales/es.json': { copy: 'config/locales/es.json', overridable: 'config/locales/es.json' },
            './config/locales/fr.json': { copy: 'config/locales/fr.json', overridable: 'config/locales/fr.json' },

          }
        }
      },//</backend>
      //  ███████╗██████╗  ██████╗ ███╗   ██╗████████╗███████╗███╗   ██╗██████╗
      //  ██╔════╝██╔══██╗██╔═══██╗████╗  ██║╚══██╔══╝██╔════╝████╗  ██║██╔══██╗
      //  █████╗  ██████╔╝██║   ██║██╔██╗ ██║   ██║   █████╗  ██╔██╗ ██║██║  ██║
      //  ██╔══╝  ██╔══██╗██║   ██║██║╚██╗██║   ██║   ██╔══╝  ██║╚██╗██║██║  ██║
      //  ██║     ██║  ██║╚██████╔╝██║ ╚████║   ██║   ███████╗██║ ╚████║██████╔╝
      //  ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═══╝╚═════╝
      //
      {
        overridable: 'frontend',
        generator: {
          targets: {

            //  ╦═╗╔═╗╔╗ ╦ ╦╦╦  ╔╦╗   ╔═╗╦  ╔═╗╦ ╦╔╦╗   ╔═╗╔╦╗╦╔═  ┌─┐┌─┐┬─┐┬┌─┐┌┬┐
            //  ╠╦╝║╣ ╠╩╗║ ║║║   ║║───║  ║  ║ ║║ ║ ║║───╚═╗ ║║╠╩╗  └─┐│  ├┬┘│├─┘ │
            //  ╩╚═╚═╝╚═╝╚═╝╩╩═╝═╩╝   ╚═╝╩═╝╚═╝╚═╝═╩╝   ╚═╝═╩╝╩ ╩  └─┘└─┘┴└─┴┴   ┴
            './scripts/rebuild-cloud-sdk.js': { onlyIf: 'caviar', copy: 'scripts/rebuild-cloud-sdk.js' },

            //  ╔═╗╔═╗╔═╗╔═╗╔╦╗╔═╗
            //  ╠═╣╚═╗╚═╗║╣  ║ ╚═╗
            //  ╩ ╩╚═╝╚═╝╚═╝ ╩ ╚═╝
            // Default assets folder and contents:
            './assets': {
              overridable: 'assets',
              generator: {
                targets: {
                  '.':                       { folder: {} },
                  './favicon.ico':           { copy: 'assets/favicon.ico' },
                  './.eslintrc':             { template: 'assets/eslintrc-override.template' },

                  './images':                     { folder: {} },
                  './images/.gitkeep':            { onlyIf: 'traditional', copy: '../../../shared-templates/gitkeep.template' },
                  './images/logo.png':      { onlyIf: 'caviar', copy: 'assets/images/logo.png' },
                  './images/icon-close.png':      { onlyIf: 'caviar', copy: 'assets/images/icon-close.png' },
                  './images/hero-cloud.png':      { onlyIf: 'caviar', copy: 'assets/images/hero-cloud.png' },
                  './images/hero-ship.png':      { onlyIf: 'caviar', copy: 'assets/images/hero-ship.png' },
                  './images/hero-sky.png':      { onlyIf: 'caviar', copy: 'assets/images/hero-sky.png' },
                  './images/hero-water.png':      { onlyIf: 'caviar', copy: 'assets/images/hero-water.png' },
                  './images/setup-email.png':      { onlyIf: 'caviar', copy: 'assets/images/setup-email.png' },
                  './images/setup-payment.png':      { onlyIf: 'caviar', copy: 'assets/images/setup-payment.png' },
                  './images/setup-customize.png':      { onlyIf: 'caviar', copy: 'assets/images/setup-customize.png' },

                  './styles':                { folder: {} },
                  './styles/importer.less':  { template: 'assets/styles/importer.less.template' },
                  './styles/layout.less':    { onlyIf: 'caviar', copy: 'assets/styles/layout.less' },
                  './styles/bootstrap-overrides.less':    { onlyIf: 'caviar', copy: 'assets/styles/bootstrap-overrides.less' },

                  './styles/components':          { onlyIf: 'caviar', folder: {} },
                  './styles/components/ajax-button.component.less': { onlyIf: 'caviar', copy: 'assets/styles/components/ajax-button.component.less' },
                  './styles/components/modal.component.less': { onlyIf: 'caviar', copy: 'assets/styles/components/modal.component.less' },
                  './styles/components/cloud-error.component.less': { onlyIf: 'caviar', copy: 'assets/styles/components/cloud-error.component.less' },
                  './styles/components/stripe-card-element.component.less': { onlyIf: 'caviar', copy: 'assets/styles/components/stripe-card-element.component.less' },

                  './styles/pages':          { onlyIf: 'caviar', folder: {} },
                  './styles/pages/account':  { onlyIf: 'caviar', folder: {} },
                  './styles/pages/account/edit-password.less': { onlyIf: 'caviar', copy: 'assets/styles/pages/account/edit-password.less' },
                  './styles/pages/account/account-overview.less': { onlyIf: 'caviar', copy: 'assets/styles/pages/account/account-overview.less' },
                  './styles/pages/account/edit-profile.less': { onlyIf: 'caviar', copy: 'assets/styles/pages/account/edit-profile.less' },
                  './styles/pages/contact.less': { onlyIf: 'caviar', copy: 'assets/styles/pages/contact.less' },
                  './styles/pages/entrance':  { onlyIf: 'caviar', folder: {} },
                  './styles/pages/entrance/confirmed-email.less':  { onlyIf: 'caviar', copy: 'assets/styles/pages/entrance/confirmed-email.less' },
                  './styles/pages/entrance/forgot-password.less':  { onlyIf: 'caviar', copy: 'assets/styles/pages/entrance/forgot-password.less' },
                  './styles/pages/entrance/login.less':  { onlyIf: 'caviar', copy: 'assets/styles/pages/entrance/login.less' },
                  './styles/pages/entrance/new-password.less':  { onlyIf: 'caviar', copy: 'assets/styles/pages/entrance/new-password.less' },
                  './styles/pages/entrance/signup.less':  { onlyIf: 'caviar', copy: 'assets/styles/pages/entrance/signup.less' },
                  './styles/pages/faq.less': { onlyIf: 'caviar', copy: 'assets/styles/pages/faq.less' },
                  './styles/pages/homepage.less': { onlyIf: 'caviar', copy: 'assets/styles/pages/homepage.less' },
                  './styles/pages/legal':  { onlyIf: 'caviar', folder: {} },
                  './styles/pages/legal/privacy.less':  { onlyIf: 'caviar', copy: 'assets/styles/pages/legal/privacy.less' },
                  './styles/pages/legal/terms.less':  { onlyIf: 'caviar', copy: 'assets/styles/pages/legal/terms.less' },
                  './styles/pages/dashboard':  { onlyIf: 'caviar', folder: {} },
                  './styles/pages/dashboard/welcome.less': { onlyIf: 'caviar', copy: 'assets/styles/pages/dashboard/welcome.less' },
                  './styles/pages/498.less': { onlyIf: 'caviar', copy: 'assets/styles/pages/498.less' },
                  './styles/pages/404.less': { onlyIf: 'caviar', copy: 'assets/styles/pages/404.less' },
                  './styles/pages/500.less': { onlyIf: 'caviar', copy: 'assets/styles/pages/500.less' },

                  './styles/mixins-and-variables':          { onlyIf: 'caviar', folder: {} },
                  './styles/mixins-and-variables/containers.less': { onlyIf: 'caviar', copy: 'assets/styles/mixins-and-variables/containers.less' },
                  './styles/mixins-and-variables/animations.less': { onlyIf: 'caviar', copy: 'assets/styles/mixins-and-variables/animations.less' },
                  './styles/mixins-and-variables/buttons.less': { onlyIf: 'caviar', copy: 'assets/styles/mixins-and-variables/buttons.less' },
                  './styles/mixins-and-variables/colors.less': { onlyIf: 'caviar', copy: 'assets/styles/mixins-and-variables/colors.less' },
                  './styles/mixins-and-variables/typography.less': { onlyIf: 'caviar', copy: 'assets/styles/mixins-and-variables/typography.less' },
                  './styles/mixins-and-variables/truncate.less': { onlyIf: 'caviar', copy: 'assets/styles/mixins-and-variables/truncate.less' },
                  './styles/mixins-and-variables/index.less': { onlyIf: 'caviar', copy: 'assets/styles/mixins-and-variables/index.less' },

                  './templates':             { folder: {} },
                  './templates/.gitkeep':    { copy: '../../../shared-templates/gitkeep.template' },

                  './js':                    { folder: {} },
                  './js/.gitkeep':           { onlyIf: 'traditional', copy: '../../../shared-templates/gitkeep.template' },
                  './js/cloud.setup.js':     { onlyIf: 'caviar', copy: 'assets/js/cloud.setup.js' },
                  './js/components':         { onlyIf: 'caviar', folder: {} },
                  './js/components/modal.component.js': { onlyIf: 'caviar', copy: 'assets/js/components/modal.component.js' },
                  './js/components/cloud-error.component.js': { onlyIf: 'caviar', copy: 'assets/js/components/cloud-error.component.js' },
                  './js/components/ajax-button.component.js': { onlyIf: 'caviar', copy: 'assets/js/components/ajax-button.component.js' },
                  './js/components/ajax-form.component.js': { onlyIf: 'caviar', copy: 'assets/js/components/ajax-form.component.js' },
                  './js/components/stripe-card-element.component.js': { onlyIf: 'caviar', copy: 'assets/js/components/stripe-card-element.component.js' },
                  './js/components/js-timestamp.component.js': { onlyIf: 'caviar', copy: 'assets/js/components/js-timestamp.component.js' },
                  './js/components/account-notification-banner.component.js': { onlyIf: 'caviar', copy: 'assets/js/components/account-notification-banner.component.js' },
                  './js/pages': { onlyIf: 'caviar', folder: {} },
                  './js/pages/account': { onlyIf: 'caviar', folder: {} },
                  './js/pages/account/edit-password.page.js': { onlyIf: 'caviar', copy: 'assets/js/pages/account/edit-password.page.js' },
                  './js/pages/account/account-overview.page.js': { onlyIf: 'caviar', copy: 'assets/js/pages/account/account-overview.page.js' },
                  './js/pages/account/edit-profile.page.js': { onlyIf: 'caviar', copy: 'assets/js/pages/account/edit-profile.page.js' },
                  './js/pages/contact.page.js': { onlyIf: 'caviar', copy: 'assets/js/pages/contact.page.js' },
                  './js/pages/dashboard': { onlyIf: 'caviar', folder: {} },
                  './js/pages/dashboard/welcome.page.js': { onlyIf: 'caviar', copy: 'assets/js/pages/dashboard/welcome.page.js' },
                  './js/pages/entrance': { onlyIf: 'caviar', folder: {} },
                  './js/pages/entrance/confirmed-email.page.js': { onlyIf: 'caviar', copy: 'assets/js/pages/entrance/confirmed-email.page.js' },
                  './js/pages/entrance/forgot-password.page.js': { onlyIf: 'caviar', copy: 'assets/js/pages/entrance/forgot-password.page.js' },
                  './js/pages/entrance/login.page.js': { onlyIf: 'caviar', copy: 'assets/js/pages/entrance/login.page.js' },
                  './js/pages/entrance/new-password.page.js': { onlyIf: 'caviar', copy: 'assets/js/pages/entrance/new-password.page.js' },
                  './js/pages/entrance/signup.page.js': { onlyIf: 'caviar', copy: 'assets/js/pages/entrance/signup.page.js' },
                  './js/pages/faq.page.js': { onlyIf: 'caviar', copy: 'assets/js/pages/faq.page.js' },
                  './js/pages/homepage.page.js': { onlyIf: 'caviar', copy: 'assets/js/pages/homepage.page.js' },
                  './js/pages/legal': { onlyIf: 'caviar', folder: {} },
                  './js/pages/legal/privacy.page.js': { onlyIf: 'caviar', copy: 'assets/js/pages/legal/privacy.page.js' },
                  './js/pages/legal/terms.page.js': { onlyIf: 'caviar', copy: 'assets/js/pages/legal/terms.page.js' },

                  './js/utilities': { onlyIf: 'caviar', folder: {} },
                  './js/utilities/open-stripe-checkout.js': { onlyIf: 'caviar', copy: 'assets/js/utilities/open-stripe-checkout.js' },

                  './dependencies':          { folder: {} },
                  './dependencies/.gitkeep': { onlyIf: 'traditional', copy: '../../../shared-templates/gitkeep.template' },

                  './dependencies/bootstrap-4': { onlyIf: 'caviar', folder: {} },
                  './dependencies/bootstrap-4/bootstrap-4.css': { onlyIf: 'caviar', copy: 'assets/dependencies/bootstrap-4/bootstrap-4.css' },
                  './dependencies/bootstrap-4/bootstrap-4.bundle.js': { onlyIf: 'caviar', copy: 'assets/dependencies/bootstrap-4/bootstrap-4.bundle.js' },

                  './dependencies/fontawesome.css': { onlyIf: 'caviar', copy: 'assets/dependencies/fontawesome.css' },

                  './dependencies/jquery.min.js': { onlyIf: 'caviar', copy: 'assets/dependencies/jquery.min.js' },
                  './dependencies/lodash.js': { onlyIf: 'caviar', copy: 'assets/dependencies/lodash.js' },
                  './dependencies/vue.js': { onlyIf: 'caviar', copy: 'assets/dependencies/vue.js' },
                  './dependencies/vue-router.js': { onlyIf: 'caviar', copy: 'assets/dependencies/vue-router.js' },
                  './dependencies/moment.js': { onlyIf: 'caviar', copy: 'assets/dependencies/moment.js' },

                  // Note that parasails.js, cloud.js, and sails.io.js are injected separately below.

                  './fonts': { onlyIf: 'caviar', folder: {} },
                  './fonts/fontawesome-webfont.eot': { onlyIf: 'caviar', copy: 'assets/fonts/fontawesome-webfont.eot' },
                  './fonts/fontawesome-webfont.svg': { onlyIf: 'caviar', copy: 'assets/fonts/fontawesome-webfont.svg' },
                  './fonts/fontawesome-webfont.ttf': { onlyIf: 'caviar', copy: 'assets/fonts/fontawesome-webfont.ttf' },
                  './fonts/fontawesome-webfont.woff': { onlyIf: 'caviar', copy: 'assets/fonts/fontawesome-webfont.woff' },
                  './fonts/fontawesome-webfont.woff2': { onlyIf: 'caviar', copy: 'assets/fonts/fontawesome-webfont.woff2' },

                }//</targets>
              }//</generator>
            },//</ assets/ >

            //  ╔╦╗╔═╗╔═╗╦╔═╔═╗
            //   ║ ╠═╣╚═╗╠╩╗╚═╗
            //   ╩ ╩ ╩╚═╝╩ ╩╚═╝
            // Default tasks/ folder and contents:
            './tasks/': {
              overridable: 'grunttasks',
              generator: {
                targets: {

                  // asset pipeline setup
                  './pipeline.js':            { template: 'tasks/pipeline.js.template' },


                  // grunt task configurations (`tasks/config/`)
                  './config/clean.js':        { copy: 'tasks/config/clean.js' },
                  './config/concat.js':       { copy: 'tasks/config/concat.js' },
                  './config/copy.js':         { copy: 'tasks/config/copy.js' },
                  './config/cssmin.js':       { copy: 'tasks/config/cssmin.js' },
                  './config/less.js':         { copy: 'tasks/config/less.js' },
                  './config/hash.js':         { copy: 'tasks/config/hash.js' },
                  './config/sails-linker.js': { copy: 'tasks/config/sails-linker.js' },
                  './config/sync.js':         { copy: 'tasks/config/sync.js' },
                  './config/uglify.js':       { copy: 'tasks/config/uglify.js' },
                  './config/babel.js':        { copy: 'tasks/config/babel.js' },

                  './config/watch.js':        { template: 'tasks/config/watch.js.template' },


                  // intermediate grunt tasklists (`tasks/register`)
                  './register/linkAssets.js':          { copy: 'tasks/register/linkAssets.js' },
                  './register/linkAssetsBuild.js':     { copy: 'tasks/register/linkAssetsBuild.js' },
                  './register/linkAssetsBuildProd.js': { copy: 'tasks/register/linkAssetsBuildProd.js' },
                  './register/syncAssets.js':          { copy: 'tasks/register/syncAssets.js' },
                  './register/compileAssets.js':       { copy: 'tasks/register/compileAssets.js' },
                  './register/polyfill.js':            { template: 'tasks/register/polyfill.js.template' },


                  // built-in grunt tasks which are automatically called by Sails (`tasks/register/`)
                  './register/build.js':               { copy: 'tasks/register/build.js' },
                  './register/buildProd.js':           { copy: 'tasks/register/buildProd.js' },
                  './register/prod.js':                { copy: 'tasks/register/prod.js' },

                  './register/default.js':             { template: 'tasks/register/default.js.template' },

                }
              }
            }//</ tasks/ >

          }
        }
      },//</frontend>


      //  ███████╗ █████╗ ██╗██╗     ███████╗   ██╗ ██████╗         ██╗███████╗
      //  ██╔════╝██╔══██╗██║██║     ██╔════╝   ██║██╔═══██╗        ██║██╔════╝
      //  ███████╗███████║██║██║     ███████╗   ██║██║   ██║        ██║███████╗
      //  ╚════██║██╔══██║██║██║     ╚════██║   ██║██║   ██║   ██   ██║╚════██║
      //  ███████║██║  ██║██║███████╗███████║██╗██║╚██████╔╝██╗╚█████╔╝███████║
      //  ╚══════╝╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚═╝╚═╝ ╚═════╝ ╚═╝ ╚════╝ ╚══════╝
      //
      // Call sails.io.js sub-generator to create the browser socket client at
      // the conventional location (in `assets/dependencies/sails.io.js`)
      'sails.io.js',


      //  ██████╗  █████╗ ██████╗  █████╗ ███████╗ █████╗ ██╗██╗     ███████╗
      //  ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔══██╗██║██║     ██╔════╝
      //  ██████╔╝███████║██████╔╝███████║███████╗███████║██║██║     ███████╗
      //  ██╔═══╝ ██╔══██║██╔══██╗██╔══██║╚════██║██╔══██║██║██║     ╚════██║
      //  ██║     ██║  ██║██║  ██║██║  ██║███████║██║  ██║██║███████╗███████║
      //  ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝╚══════╝╚══════╝
      //
      // Call parasails sub-generator to create parasails.js and cloud.js (cloud sdk)
      // at the conventional locations (in `assets/dependencies/parasails.js` and
      // `assets/dependencies/cloud.js`)
      'parasails',

    ],

    //  ███╗   ███╗██╗███████╗ ██████╗
    //  ████╗ ████║██║██╔════╝██╔════╝
    //  ██╔████╔██║██║███████╗██║
    //  ██║╚██╔╝██║██║╚════██║██║
    //  ██║ ╚═╝ ██║██║███████║╚██████╗
    //  ╚═╝     ╚═╝╚═╝╚══════╝ ╚═════╝
    //
    './.gitignore':      { copy: 'gitignore.template' },
    './.editorconfig':   { copy: 'editorconfig.template' },
    './.htmlhintrc':     { template: 'htmlhintrc.template', overridable: '.htmlhintrc' },
    './.lesshintrc':     { template: 'lesshintrc.template', overridable: '.lesshintrc' },
    './.eslintrc':       { template: 'eslintrc.template' },
    './.eslintignore':   { template: 'eslintignore.template' },
    './.npmrc':          { copy: '../../../shared-templates/npmrc.template' },

    './package.json':    { jsonfile: require('./get-package-json-data') },
    './app.js':          { copy: 'app.js.template' },

    './.sailsrc':        { jsonfile: require('./get-sailsrc-data') },
    './README.md':       { template: './README.md.template' },
  }

};


