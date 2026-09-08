const express = require('express');
const tripStateService = require("../services/tripStateService");
const profileService = require("../services/profileService");

const router = express.Router();

router.get('/:user_id', async (req, res) => {
  try {
    const user_id = req.params.user_id;
    const session_id = req.query.session_id || "default_session";

    const tripState = await tripStateService.getTripState(user_id);

    if (!tripState || !tripState.destination) {
      return res.json({ success: true, hasDisruption: false });
    }

    const randomChance = Math.random();
    if (randomChance < 0.05) {
      const disruptions = [
        `Heavy thunderstorm detected in ${tripState.destination}. Outdoor activities may be cancelled.`,
        `Major traffic accident reported on the main highway to ${tripState.destination}, expecting 2 hours delay.`,
        `Unexpected road closures in the center of ${tripState.destination} due to local event.`
      ];

      const randomDisruption = disruptions[Math.floor(Math.random() * disruptions.length)];

      console.log(`[DISRUPTION] Detected disruption: ${randomDisruption}`);

      return res.json({
        success: true,
        hasDisruption: true,
        message: randomDisruption,
        ai_message: "I noticed a disruption in our route. Would you like me to find an alternative?"
      });
    }

    res.json({ success: true, hasDisruption: false });
  } catch (error) {
    console.error('Disruption Check Error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;
