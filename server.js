require("dotenv").config();
const path = require("path");
const express = require("express");
const cors = require("cors");

const chatRoute = require("./src/routes/chat");
const voiceRoute = require("./src/routes/voice");
const ttsRoute = require("./src/routes/tts");
const disruptionRoute = require("./src/routes/disruption");
const tripStateService = require("./src/services/tripStateService");
const profileService = require("./src/services/profileService");

const app = express();

app.use(cors());
app.use(express.json());

app.use(express.static(path.join(__dirname, "public")));

app.use("/api", chatRoute);
app.use("/api", voiceRoute);
app.use("/api/tts", ttsRoute);
app.use("/api/check-disruption", disruptionRoute);

app.get("/api/health", (req, res) => {
  res.json({ status: "ok", message: "iOS Siri AI Chatbot Server is online." });
});

app.get("/api/state/:user_id", async (req, res) => {
  try {
    const user_id = req.params.user_id;
    const tripState = await tripStateService.getTripState(user_id);
    const profile = await profileService.getProfile(user_id);
    res.json({ success: true, tripState, profile });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`✨ Nova AI Chatbot Server active on http://localhost:${PORT}`);
});