// /**
//  * Module dependencies
//  */

// var _ = require('lodash');
// var generate = require('../lib');



// var scope = {};

// generate({
//   targets: {
//     '.': {
//       exec: function (scope, cb) {
//         console.log('Test A');
//         console.log('Current destPath :: '+scope.rootPath);
//         cb();
//       }
//     },

//     './erm': {
//       targets: {
//         '.': {
//           exec: function (scope, cb) {
//             console.log('Test B');
//             console.log('Current destPath :: '+scope.rootPath);
//             cb();
//           }
//         },

//         'evenDeeper': {
//           targets: {
//             '.': {
//               targets: {
//                 '.': {
//                   exec: function (scope, cb) {
//                     console.log('Test C');
//                     console.log('Current destPath :: '+scope.rootPath);
//                     cb();
//                   }
//                 }
//               }
//             }
//           }
//         }
//       }
//     }
//   }
// }, scope, function (err) {
//   if (err) {
//     console.log(err);
//     return;
//   }

//   console.log('Done.');

// });
