/// Explicit capability contract. It prevents Nova UI and future integrations
/// from claiming support for inputs or actions that have no provider yet.
enum NovaCapabilityStatus { available, integrationRequired, unavailable }

enum NovaCapability {
  foregroundWake,
  manualVoice,
  textChat,
  tts,
  vision,
  cameraUnderstanding,
  backgroundWake,
  lockedScreenWake,
  streamingResponses,
  voiceConfirmation,
}

class NovaCapabilityRegistry {
  NovaCapabilityRegistry._();

  static const statuses = <NovaCapability, NovaCapabilityStatus>{
    // Android SpeechRecognizer is a foreground recognition boundary, not a
    // dependable low-power hotword engine on every device/provider.
    NovaCapability.foregroundWake: NovaCapabilityStatus.integrationRequired,
    NovaCapability.manualVoice: NovaCapabilityStatus.available,
    NovaCapability.textChat: NovaCapabilityStatus.available,
    NovaCapability.tts: NovaCapabilityStatus.available,
    NovaCapability.vision: NovaCapabilityStatus.integrationRequired,
    NovaCapability.cameraUnderstanding:
        NovaCapabilityStatus.integrationRequired,
    NovaCapability.backgroundWake: NovaCapabilityStatus.integrationRequired,
    NovaCapability.lockedScreenWake: NovaCapabilityStatus.integrationRequired,
    NovaCapability.streamingResponses: NovaCapabilityStatus.integrationRequired,
    NovaCapability.voiceConfirmation: NovaCapabilityStatus.available,
  };

  static NovaCapabilityStatus statusOf(NovaCapability capability) =>
      statuses[capability] ?? NovaCapabilityStatus.unavailable;
}
