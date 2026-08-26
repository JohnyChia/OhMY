/**
 * Web Speech API Controller for Nova Voice Interaction
 */
class NovaSpeechEngine {
  constructor(options = {}) {
    this.onResultCallback = options.onResult || null;
    this.onStateChangeCallback = options.onStateChange || null;
    this.onEndCallback = options.onEnd || null;
    this.onErrorCallback = options.onError || null;
    this.ttsEnabled = true;

    this.mediaRecorder = null;
    this.audioChunks = [];
    this.isListening = false;
    this.speechRequestId = 0;
    this.audioElement = new Audio(); // Reusable audio element for autoplay policy
  }

  async startListening() {
    if (this.isListening) return;
    
    // Unlock HTML5 Audio autoplay policy by playing a silent sound on user interaction
    this.audioElement.src = "data:audio/wav;base64,UklGRigAAABXQVZFZm10IBIAAAABAAEARKwAAIhYAQACABAAAABkYXRhAgAAAAEA";
    this.audioElement.play().catch(() => {});

    const fallbackToBrowserSTT = () => {
      console.warn("[VOICE] Whisper failed or unsupported. Falling back to Browser STT");
      const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
      
      if (SpeechRecognition) {
        this.recognition = new SpeechRecognition();
        this.recognition.continuous = true;
        this.recognition.interimResults = true;
        this.recognition.lang = 'en-MY'; // Malaysian English supports local nouns and Manglish well
        console.log("[VOICE-BROWSER-STT] Web Speech API started");
        
        this.recognition.onstart = () => {
          this.isListening = true;
          if (this.onStateChangeCallback) this.onStateChangeCallback('listening');
        };

        this.recognition.onresult = (event) => {
          let interimTranscript = '';
          let finalTranscript = '';

          for (let i = event.resultIndex; i < event.results.length; ++i) {
            if (event.results[i].isFinal) {
              finalTranscript += event.results[i][0].transcript;
            } else {
              interimTranscript += event.results[i][0].transcript;
            }
          }

          if (this.onResultCallback) {
            if (finalTranscript.trim() !== '') {
              console.log("[VOICE-BROWSER-STT] Raw transcript:", finalTranscript);
              console.log("[VOICE-FRONTEND] Sending transcript to /chat:", finalTranscript);
            }
            this.onResultCallback({
              interim: interimTranscript,
              final: finalTranscript
            });
          }
        };

        this.recognition.onerror = (event) => {
          console.error("Speech recognition error:", event.error);
          if (this.onErrorCallback) this.onErrorCallback(event.error);
          this.stopListening();
        };

        this.recognition.onend = () => {
          this.isListening = false;
          if (this.onStateChangeCallback) this.onStateChangeCallback('idle');
          if (this.onEndCallback) this.onEndCallback();
        };

        try {
          this.recognition.start();
        } catch (e) {
          console.error("Failed to start fallback recognition", e);
        }
      } else {
        console.error("Browser Web Speech API not supported.");
        if (this.onStateChangeCallback) this.onStateChangeCallback('idle');
      }
    };

    console.log("[VOICE-FRONTEND] STT path selected: whisper");
    
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ 
        audio: { autoGainControl: true, echoCancellation: true, noiseSuppression: true }
      });
      this.mediaRecorder = new MediaRecorder(stream);
      this.audioChunks = [];

      const audioContext = new (window.AudioContext || window.webkitAudioContext)();
      const analyser = audioContext.createAnalyser();
      analyser.minDecibels = -70;
      const microphone = audioContext.createMediaStreamSource(stream);
      microphone.connect(analyser);
      
      const dataArray = new Uint8Array(analyser.frequencyBinCount);
      let silenceTimer = null;

      const checkSilence = () => {
        if (!this.isListening) return;
        analyser.getByteFrequencyData(dataArray);
        let sum = 0;
        for (let i = 0; i < dataArray.length; i++) sum += dataArray[i];
        if (sum / dataArray.length < 5) {
          if (!silenceTimer) silenceTimer = setTimeout(() => { if (this.isListening) this.stopListening(); }, 3000);
        } else {
          if (silenceTimer) { clearTimeout(silenceTimer); silenceTimer = null; }
        }
        requestAnimationFrame(checkSilence);
      };

      this.mediaRecorder.ondataavailable = (e) => { if (e.data.size > 0) this.audioChunks.push(e.data); };
      this.mediaRecorder.onstart = () => {
        console.log("[VOICE-FRONTEND] Recording started");
        this.isListening = true;
        if (this.onStateChangeCallback) this.onStateChangeCallback('listening');
        checkSilence();
      };
      this.mediaRecorder.onstop = async () => {
        console.log("[VOICE-FRONTEND] Recording stopped");
        this.isListening = false;
        if (silenceTimer) clearTimeout(silenceTimer);
        if (audioContext.state !== 'closed') audioContext.close();
        if (this.onStateChangeCallback) this.onStateChangeCallback('thinking');

        const audioBlob = new Blob(this.audioChunks, { type: 'audio/webm' });
        this.audioChunks = [];
        stream.getTracks().forEach(track => track.stop());

        try {
          const formData = new FormData();
          formData.append('audio', audioBlob, 'speech.webm');
          const uid = localStorage.getItem("Nova_user_id");
          if (uid) formData.append('user_id', uid);
          
          const response = await fetch('/api/transcribe', { method: 'POST', body: formData });
          const data = await response.json();
          
          if (data.success && data.text) {
             console.log("[VOICE-FRONTEND] Transcript received:", data.text);
             console.log("[VOICE-FRONTEND] Sending transcript to /chat:", data.text);
             if (this.onResultCallback) this.onResultCallback({ interim: '', final: data.text });
          } else {
             console.error("[VOICE-FRONTEND] Whisper failed:", data.error);
             fallbackToBrowserSTT();
          }
        } catch (error) {
          console.error("[VOICE-FRONTEND] Whisper request failed:", error.message);
          fallbackToBrowserSTT();
        } finally {
           if (this.onStateChangeCallback) this.onStateChangeCallback('idle');
           if (this.onEndCallback) this.onEndCallback();
        }
      };
      this.mediaRecorder.start();
    } catch (err) {
      console.warn("[VOICE] Microphone access or MediaRecorder failed:", err.message);
      fallbackToBrowserSTT();
    }
  }

  stopListening() {
    if (this.recognition) {
      this.recognition.stop();
    } else if (this.mediaRecorder && this.mediaRecorder.state !== 'inactive') {
      this.mediaRecorder.stop();
    }
  }

  setLanguage(langCode) {
    // Deprecated: Language is now auto-detected by Whisper API
  }

  async speak(text, lang, onEndCallback) {
    if (typeof lang === 'function') {
      onEndCallback = lang;
      lang = null;
    }
    if (!this.ttsEnabled || !text) {
      if (onEndCallback) onEndCallback();
      return;
    }

    const requestId = ++this.speechRequestId;
    
    // Stop any currently playing audio
    if (this.currentAudio) {
      this.currentAudio.pause();
      this.currentAudio = null;
    }

    if (this.onStateChangeCallback) this.onStateChangeCallback('thinking');

    try {
      const res = await fetch('/api/tts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text, language: lang })
      });
      
      const data = await res.json();
      if (!data.success || !data.audioUrls || data.audioUrls.length === 0) {
        throw new Error("No audio returned");
      }

      if (this.onStateChangeCallback) this.onStateChangeCallback('speaking');

      // Play audio URLs sequentially
      let currentIndex = 0;
      
      const playNext = () => {
        if (requestId !== this.speechRequestId) return; // Cancelled
        if (currentIndex >= data.audioUrls.length) {
          if (this.onStateChangeCallback) this.onStateChangeCallback('idle');
          if (onEndCallback) onEndCallback();
          return;
        }

        this.audioElement.src = data.audioUrls[currentIndex];
        this.currentAudio = this.audioElement;
        
        this.audioElement.onended = () => {
          currentIndex++;
          playNext();
        };
        
        this.audioElement.onerror = (err) => {
          console.warn("Audio playback error:", err);
          currentIndex++;
          playNext();
        };

        this.audioElement.play().catch(e => {
          console.warn("Auto-play prevented:", e);
          if (this.onStateChangeCallback) this.onStateChangeCallback('idle');
          if (onEndCallback) onEndCallback();
        });
      };

      playNext();
      
    } catch (err) {
      console.error("TTS fetch error:", err);
      if (this.onStateChangeCallback) this.onStateChangeCallback('idle');
      if (onEndCallback) onEndCallback();
    }
  }

  stopSpeaking() {
    this.speechRequestId += 1;
    if (this.currentAudio) {
      this.currentAudio.pause();
      this.currentAudio.currentTime = 0;
      this.currentAudio = null;
    }
    if (this.audioElement) {
      this.audioElement.pause();
      this.audioElement.currentTime = 0;
    }
    if (this.onStateChangeCallback) this.onStateChangeCallback('idle');
  }

  toggleTTS() {
    this.ttsEnabled = !this.ttsEnabled;
    if (!this.ttsEnabled) {
      this.stopSpeaking();
      if ('speechSynthesis' in window) {
        window.speechSynthesis.cancel();
      }
    }
    return this.ttsEnabled;
  }
}
