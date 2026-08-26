/**
 * Travel AI Nova Assistant — Application Controller
 */

document.addEventListener("DOMContentLoaded", () => {
  // ── 1. Session & User Management ─────────────────────────────────────────
  let userId = localStorage.getItem("Nova_user_id");
  if (!userId) {
    userId = "usr_" + Math.random().toString(36).substring(2, 10);
    localStorage.setItem("Nova_user_id", userId);
  }

  // ── 2. DOM Elements ───────────────────────────────────────────────────────
  const heroSection      = document.getElementById("nova-hero");
  const chatStream       = document.getElementById("chat-stream");
  const chatForm         = document.getElementById("chat-form");
  const userInput        = document.getElementById("user-input");
  const btnMic           = document.getElementById("btn-mic");
  const btnSend          = document.getElementById("btn-send");
  const btnTTSToggle     = document.getElementById("btn-tts-toggle");
  const btnResetSession  = document.getElementById("btn-reset-session");
  const statusBar        = document.getElementById("nova-status-bar");
  const statusText       = document.getElementById("status-text");
  const miniOrbTrigger   = document.getElementById("mini-orb-trigger");
  const typingIndicator  = document.getElementById("typing-indicator");

  // ── 3. Initialize Nova Orb Visualizers ───────────────────────────────────
  const heroOrb   = new NovaOrb("hero-orb-canvas");
  const footerOrb = new NovaOrb("footer-orb-canvas");
  let isRequestInFlight = false;
  let lastRenderedItinerarySignature = null;
  let currentVoiceTranscript = "";
  let voiceDebounceTimer = null;
  const VOICE_DEBOUNCE_MS = 2000;
  
  function getItinerarySignature(itinerary) {
    if (!itinerary || !Array.isArray(itinerary)) return null;
    return JSON.stringify(itinerary);
  }

  // ── 4. Helpers ────────────────────────────────────────────────────────────

  function setInputBusy(isBusy) {
    isRequestInFlight = isBusy;
    btnSend.disabled  = isBusy;
    btnMic.disabled   = isBusy;
    userInput.disabled = isBusy;
  }

  function escapeHtml(value) {
    return String(value ?? "").replace(/[&<>"']/g, (c) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;"
    }[c]));
  }

  /**
   * Convert **bold** markdown to <strong> tags inside an already-escaped string.
   * We work on the escaped text, so it is XSS-safe.
   */
  function renderMarkdown(text) {
    const escaped = escapeHtml(text);
    // **bold** → <strong>bold</strong>
    return escaped.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");
  }

  function showTypingIndicator() {
    if (!typingIndicator) return;
    typingIndicator.classList.remove("hidden");
    // Move it to the bottom of chat-stream
    chatStream.appendChild(typingIndicator);
    chatStream.scrollTop = chatStream.scrollHeight;
  }

  function hideTypingIndicator() {
    if (!typingIndicator) return;
    typingIndicator.classList.add("hidden");
  }

  function setAppNovaState(state, message = "") {
    document.body.className = "nova-theme " + state;
    heroOrb.setState(state);
    footerOrb.setState(state);

    statusBar.className = "nova-status-bar " + state;
    if (message) {
      statusText.textContent = message;
    } else {
      const labels = {
        listening: "Listening to you...",
        thinking:  "Nova is thinking...",
        speaking:  "Nova is speaking..."
      };
      statusText.textContent = labels[state] || "Tap the orb or type your travel question";
    }
  }

  function scrollToBottom() {
    requestAnimationFrame(() => {
      chatStream.scrollTop = chatStream.scrollHeight;
    });
  }

  // ── 5. Initialize Speech Engine ───────────────────────────────────────────
  const speechEngine = new NovaSpeechEngine({
    onStateChange: (state) => {
      setAppNovaState(state);
      if (state === "listening") {
        btnMic.classList.add("active");
      } else {
        btnMic.classList.remove("active");
      }
    },
    onResult: (res) => {
      // Accumulate speech internally without dirtying the text input box
      if (res.final) {
        currentVoiceTranscript = (currentVoiceTranscript + " " + res.final).trim();
      } else if (res.interim) {
        // We track interim just to keep the timer alive, but don't permanently store it
      }

      // Only start debounce if we actually have accumulated speech
      if (currentVoiceTranscript.trim()) {
        clearTimeout(voiceDebounceTimer);
        voiceDebounceTimer = setTimeout(() => {
          if (speechEngine.isListening) {
            speechEngine.stopListening();
          }
        }, VOICE_DEBOUNCE_MS);
      }
    },
    onEnd: () => {
      clearTimeout(voiceDebounceTimer);
      const text = currentVoiceTranscript.trim();
      currentVoiceTranscript = ""; // Reset for next session
      
      if (text && !isRequestInFlight) {
        handleUserSubmit(text, true);
      }
    },
    onError: (errorMsg) => {
      setAppNovaState("idle", "Speech recognition failed");
      appendMessage("assistant", "Sorry, I couldn't hear you clearly or there was a network issue. Please try again.");
    }
  });

  // ── 6. Mic & TTS Buttons ──────────────────────────────────────────────────
  function toggleMic() {
    if (speechEngine.isListening) {
      speechEngine.stopListening();
    } else {
      if (typeof speechEngine.stopSpeaking === 'function') {
        speechEngine.stopSpeaking();
      }
      speechEngine.startListening();
    }
  }

  btnMic.addEventListener("click", toggleMic);
  miniOrbTrigger.addEventListener("click", toggleMic);

  btnTTSToggle.addEventListener("click", () => {
    const isEnabled = speechEngine.toggleTTS();
    if (isEnabled) {
      btnTTSToggle.classList.remove("muted");
      btnTTSToggle.innerHTML = '<i class="ri-volume-up-line"></i>';
    } else {
      btnTTSToggle.classList.add("muted");
      btnTTSToggle.innerHTML = '<i class="ri-volume-mute-line"></i>';
    }
  });

  btnResetSession.addEventListener("click", () => {
    userId = "usr_" + Math.random().toString(36).substring(2, 10);
    localStorage.setItem("Nova_user_id", userId);
    // Clear all messages except the typing indicator
    Array.from(chatStream.children).forEach((child) => {
      if (child.id !== "typing-indicator") child.remove();
    });
    hideTypingIndicator();
    chatStream.classList.add("hidden");
    heroSection.style.display = "flex";
    setAppNovaState("idle", "New session started — where to next?");
  });

  // ── 7. Suggestion Chips ───────────────────────────────────────────────────
  document.querySelectorAll(".chip").forEach((chip) => {
    chip.addEventListener("click", () => {
      const promptText = chip.getAttribute("data-prompt");
      userInput.value = promptText;
      handleUserSubmit(promptText, false);
    });
  });

  // ── 8. Form Submission ────────────────────────────────────────────────────
  chatForm.addEventListener("submit", (e) => {
    e.preventDefault();
    const text = userInput.value.trim();
    if (text) handleUserSubmit(text, false);
  });

  // ── 9. Main Chat Submission Logic ─────────────────────────────────────────
  async function handleUserSubmit(message, isVoice = false) {
    if (isRequestInFlight || !message || !message.trim()) return;

    setInputBusy(true);
    // Only clear visual input box if it was a text submission
    if (!isVoice) {
      userInput.value = "";
    }
    
    // Explicitly stop listening in case this was triggered by button press mid-speech
    speechEngine.stopListening();

    // Hide hero on first message
    if (heroSection.style.display !== "none") {
      heroSection.style.display = "none";
      chatStream.classList.remove("hidden");
    }

    // Show Nova thinking states
    setAppNovaState("thinking");
    showTypingIndicator();

    // Only display the user's text bubble if they typed it manually
    if (!isVoice) {
      appendMessage("user", message);
    }

    try {
      const response = await fetch("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ user_id: userId, message: message, isVoice })
      });

      const data = await response.json().catch(() => ({}));

      hideTypingIndicator();

      if (response.ok && data.success) {
        setAppNovaState("idle");
        appendAssistantResponse(data);

        // Speak the reply via TTS only if input was via voice
        if (data.reply && isVoice) {
          const langCode = data.languageCode || "en";
          speechEngine.speak(data.reply, langCode);
        }
      } else {
        setAppNovaState("idle", "Error processing your request");
        appendMessage("assistant", "Sorry, I ran into an issue: " + (data.error || "Unknown error"));
      }
    } catch (err) {
      console.error("Fetch API error:", err);
      hideTypingIndicator();
      setAppNovaState("idle", "Connection failed");
      appendMessage("assistant", "Sorry, I can't connect to the Travel AI server right now. Please try again.");
    } finally {
      setInputBusy(false);
      userInput.focus();
    }
  }

  // ── 10. Render User Bubble ────────────────────────────────────────────────
  function appendMessage(role, text) {
    const container = document.createElement("div");
    container.className = `chat-bubble-container ${role}`;

    const label = document.createElement("div");
    label.className = "message-label";
    label.textContent = role === "user" ? "You" : "Nova";

    const bubble = document.createElement("div");
    bubble.className = "chat-bubble";

    if (role === "assistant") {
      // Support **bold** markdown only for assistant replies (XSS-safe)
      bubble.innerHTML = renderMarkdown(text);
    } else {
      bubble.textContent = text;
    }

    container.appendChild(label);
    container.appendChild(bubble);

    // Insert before typing indicator if present
    if (typingIndicator && chatStream.contains(typingIndicator)) {
      chatStream.insertBefore(container, typingIndicator);
    } else {
      chatStream.appendChild(container);
    }

    scrollToBottom();
  }

  // ── 11. Render Assistant Response & Interactive Cards ─────────────────────
  function appendAssistantResponse(data) {
    const container = document.createElement("div");
    container.className = "chat-bubble-container assistant";

    const label = document.createElement("div");
    label.className = "message-label";
    label.textContent = "Nova";

    const bubble = document.createElement("div");
    bubble.className = "chat-bubble";
    bubble.innerHTML = renderMarkdown(data.reply || "Here is what I found for you:");

    if (data.language) {
      const badgeWrapper = document.createElement("div");
      badgeWrapper.style.cssText = "display: flex; justify-content: flex-end; margin-top: 8px;";
      
      const langBadge = document.createElement("div");
      langBadge.className = "language-badge";
      langBadge.textContent = "DETECTED: " + data.language.toUpperCase();
      langBadge.style.cssText = "font-size: 0.65rem; color: rgba(255,255,255,0.7); font-weight: 700; background: rgba(0,0,0,0.25); padding: 4px 8px; border-radius: 6px; border: 1px solid rgba(255,255,255,0.1);";
      
      badgeWrapper.appendChild(langBadge);
      bubble.appendChild(badgeWrapper);
    }

    container.appendChild(label);
    container.appendChild(bubble);

    const intentName = data.intent ? data.intent.intent : "";

    let shouldRenderItinerary = false;
    let currentItinSig = null;

    if (data.trip_state && Array.isArray(data.trip_state.itinerary) && data.trip_state.itinerary.length > 0) {
      currentItinSig = getItinerarySignature(data.trip_state.itinerary);
      const isExplicitIntent = ["plan_trip", "modify_trip", "generate_itinerary"].includes(intentName);
      const isNewOrUpdated = currentItinSig !== lastRenderedItinerarySignature;
      
      if (isExplicitIntent || isNewOrUpdated) {
        shouldRenderItinerary = true;
      }
    }

    // Attach a Nova Widget Card if applicable
    if (data.tool_result && intentName !== "generate_itinerary") {
      const card = createNovaWidgetCard(data.intent, data.tool_result, data.trip_state);
      if (card) container.appendChild(card);
    } 
    
    if (shouldRenderItinerary) {
      const card = createItineraryCard(data.trip_state.itinerary, data.trip_state.destination);
      if (card) {
        container.appendChild(card);
        lastRenderedItinerarySignature = currentItinSig;
      }
    }

    // Insert before typing indicator
    if (typingIndicator && chatStream.contains(typingIndicator)) {
      chatStream.insertBefore(container, typingIndicator);
    } else {
      chatStream.appendChild(container);
    }

    scrollToBottom();
  }

  // ── 12. Nova Widget Card Builder ──────────────────────────────────────────
  function createNovaWidgetCard(intentObj, toolResult, tripState) {
    const intentName = intentObj ? intentObj.intent : "";

    // 12a. Itinerary Card
    if (toolResult && Array.isArray(toolResult.days)) {
      return createItineraryCard(toolResult.days, tripState ? tripState.destination : "");
    }

    // 12b. Weather Card
    if (intentName === "weather_check" || (toolResult && (toolResult.weather || toolResult.location))) {
      const card = document.createElement("div");
      card.className = "nova-card";
      const loc = (toolResult && toolResult.location) ||
        (intentObj && intentObj.parameters && intentObj.parameters.destination) ||
        (tripState ? tripState.destination : "Destination");
      const weatherText = (toolResult && toolResult.weather) || "Partly cloudy, 28°C – 31°C";

      card.innerHTML = `
        <div class="nova-card-header">
          <div class="nova-card-title"><i class="ri-sun-cloudy-line"></i> Weather Report</div>
          <span class="nova-card-badge">Nova Forecast</span>
        </div>
        <div class="weather-widget">
          <i class="ri-cloud-sun-line weather-icon"></i>
          <div class="weather-info">
            <span class="weather-location">${escapeHtml(loc)}</span>
            <span class="weather-detail">${escapeHtml(weatherText)}</span>
          </div>
        </div>
      `;
      return card;
    }

    // 12c. Recommendation Card
    if (intentName === "recommend_place" || (toolResult && toolResult.recommendations)) {
      const card = document.createElement("div");
      card.className = "nova-card";
      const category = toolResult.category || "Must Visit";
      const recs = toolResult.recommendations || [];

      const listHtml = Array.isArray(recs)
        ? recs.map((r) => {
            if (typeof r === "object") {
              return `<div class="itinerary-day" style="margin-bottom:0.5rem;">
                <div class="itinerary-day-title">
                  ${escapeHtml(r.name)}
                  <span style="font-size:0.75rem;color:#f59e0b;margin-left:auto;">★ ${escapeHtml(String(r.rating || 4.8))}</span>
                </div>
                <div class="itinerary-desc">${escapeHtml(r.description || "")}</div>
              </div>`;
            }
            return `<div class="itinerary-day" style="margin-bottom:0.5rem;"><div class="itinerary-day-title">${escapeHtml(r)}</div></div>`;
          }).join("")
        : "";

      card.innerHTML = `
        <div class="nova-card-header">
          <div class="nova-card-title"><i class="ri-map-pin-user-line"></i> Nova Recommendations</div>
          <span class="nova-card-badge">${escapeHtml(category)}</span>
        </div>
        <div>${listHtml}</div>
      `;
      return card;
    }

    // 12d. Traffic Card
    if (intentName === "traffic_check" || (toolResult && toolResult.traffic)) {
      const card = document.createElement("div");
      card.className = "nova-card";
      const loc = (toolResult && toolResult.location) ||
        (intentObj && intentObj.parameters && intentObj.parameters.destination) || "Your Route";
      const trafficInfo = (toolResult && toolResult.traffic) || "Traffic conditions are moderate at the moment.";

      card.innerHTML = `
        <div class="nova-card-header">
          <div class="nova-card-title"><i class="ri-traffic-line"></i> Live Traffic</div>
          <span class="nova-card-badge" style="background:rgba(245,158,11,0.18);color:#fcd34d;">Live</span>
        </div>
        <div class="weather-widget">
          <i class="ri-road-map-line" style="font-size:2.4rem;color:#f59e0b;"></i>
          <div class="weather-info">
            <span class="weather-location">${escapeHtml(loc)}</span>
            <span class="weather-detail">${escapeHtml(trafficInfo)}</span>
          </div>
        </div>
      `;
      return card;
    }

    // 12e. Reroute Card
    if (intentName === "reroute_trip" || (toolResult && toolResult.reroute)) {
      const card = document.createElement("div");
      card.className = "nova-card";
      const rerouteInfo = (toolResult && (toolResult.reroute || toolResult.message)) ||
        "Alternative route found to avoid delays.";

      card.innerHTML = `
        <div class="nova-card-header">
          <div class="nova-card-title"><i class="ri-route-line"></i> Rerouted Trip</div>
          <span class="nova-card-badge" style="background:rgba(16,185,129,0.18);color:#6ee7b7;">Updated</span>
        </div>
        <div class="weather-widget">
          <i class="ri-navigation-line" style="font-size:2.4rem;color:#10b981;"></i>
          <div class="weather-info">
            <span class="weather-location">Alternative Route</span>
            <span class="weather-detail">${escapeHtml(String(rerouteInfo))}</span>
          </div>
        </div>
      `;
      return card;
    }

    // 12f. Profile / Trip State Update Card
    if (
      ["update_profile", "plan_trip", "modify_trip"].includes(intentName) &&
      tripState &&
      (tripState.destination || (tripState.interest && tripState.interest.length > 0))
    ) {
      const card = document.createElement("div");
      card.className = "nova-card";
      const destination = tripState.destination || "Not set";
      const duration    = tripState.duration ? `${tripState.duration} Days` : "Not set";
      const interests   = Array.isArray(tripState.interest) ? tripState.interest.join(", ") : "General";

      card.innerHTML = `
        <div class="nova-card-header">
          <div class="nova-card-title"><i class="ri-suitcase-line"></i> Active Trip Overview</div>
          <span class="nova-card-badge">Updated</span>
        </div>
        <div class="state-grid">
          <div class="state-item">
            <div class="state-item-label">Destination</div>
            <div class="state-item-value">${escapeHtml(destination)}</div>
          </div>
          <div class="state-item">
            <div class="state-item-label">Duration</div>
            <div class="state-item-value">${escapeHtml(duration)}</div>
          </div>
          <div class="state-item">
            <div class="state-item-label">Interests</div>
            <div class="state-item-value">${escapeHtml(interests)}</div>
          </div>
        </div>
      `;
      return card;
    }

    return null;
  }

  // ── 13. Build Itinerary Timeline Card ─────────────────────────────────────
  function createItineraryCard(days, destination) {
    const card = document.createElement("div");
    card.className = "nova-card";

    const daysHtml = days.map((d) => `
      <div class="itinerary-day">
        <div class="itinerary-day-title">
          <span>Day ${escapeHtml(String(d.day))}: ${escapeHtml(d.title)}</span>
          <span class="nova-card-badge" style="margin-left:auto;text-transform:capitalize;">
            ${escapeHtml(d.category || "General")}
          </span>
        </div>
        <div class="itinerary-location">
          <i class="ri-map-pin-line"></i> ${escapeHtml(d.location)}
        </div>
        <div class="itinerary-desc">${escapeHtml(d.description)}</div>
      </div>
    `).join("");

    card.innerHTML = `
      <div class="nova-card-header">
        <div class="nova-card-title">
          <i class="ri-calendar-event-line"></i>
          ${escapeHtml(destination ? destination + " Itinerary" : "Travel Plan")}
        </div>
        <span class="nova-card-badge">${days.length} Days</span>
      </div>
      <div class="itinerary-list">${daysHtml}</div>
    `;

    return card;
  }

  // ── 14. Disruption Polling ────────────────────────────────────────────────
  setInterval(async () => {
    // Only poll if we have a user and we're not busy
    if (!userId || isRequestInFlight) return;
    
    try {
      const res = await fetch(`/api/check-disruption/${userId}`);
      const data = await res.json();
      
      if (data.success && data.hasDisruption && data.message) {
        console.warn("Disruption detected:", data.message);
        
        // Visually show an alert banner
        setAppNovaState("idle", "🚨 Disruption Detected! Rerouting...");
        
        // Auto-send a hidden system message to the agent to trigger reroute
        const systemAlertMessage = `[SYSTEM ALERT] DISRUPTION DETECTED: ${data.message}. Please inform the user immediately in their preferred language, explain the disruption, and suggest an alternative or rerouted plan.`;
        
        // Send it without showing it as a user bubble
        setInputBusy(true);
        setAppNovaState("thinking");
        showTypingIndicator();
        
        const response = await fetch("/api/chat", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ user_id: userId, message: systemAlertMessage })
        });
        
        const responseData = await response.json();
        hideTypingIndicator();
        
        if (response.ok && responseData.success) {
          setAppNovaState("idle");
          appendAssistantResponse(responseData);
          
          // If TTS is enabled, read it aloud automatically
          if (speechEngine.ttsEnabled) {
            const lang = responseData.intent && responseData.intent.parameters && responseData.intent.parameters.language;
            speechEngine.speak(responseData.reply, lang);
          }
        } else {
          setInputBusy(false);
          setAppNovaState("idle");
        }
      }
    } catch (err) {
      // Ignore polling errors to prevent console spam
    }
  }, 30000); // 30 seconds
});
