// ONE serverless function for the whole API (Vercel Hobby limit: 12
// functions per deployment). Dispatches to lib/router.js.
// Required catch-all [...path] matches /api/* at ANY depth. (The optional
// [[...path]] form only matched a single segment on this project, so
// /api/messages/:id/react etc. 404'd at the edge — do not switch back.)
const route = require('../lib/router');

module.exports = (req, res) => route(req, res);
