// The recommender owns this taxonomy. Nova consumes it directly so additions,
// removals, and spelling changes cannot drift into a second hard-coded list.
const {
  GENERAL_TAGS,
  CULTURAL_TAGS,
} = require('../../../preference_recommender/tagging-service');

const ATTRACTION_TAGS = Object.freeze([
  ...GENERAL_TAGS,
  ...CULTURAL_TAGS,
]);

module.exports = {
  ATTRACTION_TAGS
};
