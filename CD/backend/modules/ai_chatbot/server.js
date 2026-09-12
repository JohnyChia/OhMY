require("dotenv").config();
const path = require("path");
const express = require("express");
const cors = require("cors");

const chatRoute = require("./src/routes/chat");
const voiceRoute = require("./src/routes/voice");
const attachmentRoute = require("./src/routes/attachments");
const ttsRoute = require("./src/routes/tts");
const disruptionRoute = require("./src/routes/disruption");
const tripStateService = require("./src/services/tripStateService");
const profileService = require("./src/services/profileService");
const requireNovaUser = require('./src/middleware/requireNovaUser');

const app = express();

app.use(cors());
app.use(express.json());

app.use(express.static(path.join(__dirname, "public")));

app.use("/api", chatRoute);
app.use("/api", voiceRoute);
app.use("/api", attachmentRoute);
app.use("/api/tts", ttsRoute);
app.use("/api/check-disruption", disruptionRoute);

app.get("/api/health", (req, res) => {
  res.json({ status: "ok", message: "Nova AI Chatbot Server is online." });
});

app.get("/api/state/:user_id", requireNovaUser, async (req, res) => {
  try {
    if (req.params.user_id !== req.novaUserId) {
      return res.status(403).json({ success: false, error: 'Authenticated user does not match request user.' });
    }
    const user_id = req.novaUserId;
    const tripState = await tripStateService.getTripState(user_id);
    const profile = await profileService.getProfile(user_id);
    res.json({ success: true, tripState, profile });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// The main recommendation backend owns port 3000 during local development.
const PORT = process.env.PORT || 3001;

app.listen(PORT, () => {
  console.log(`✨ Nova AI Chatbot Server active on http://localhost:${PORT}`);
});
