enum NovaAttachmentType { image, file, communityDiscovery }

enum NovaAttachmentAnalysisStatus {
  selected,
  analyzing,
  ready,
  failed,
  providerUnavailable,
  rejected,
}

class NovaAttachment {
  const NovaAttachment({
    required this.name,
    required this.path,
    required this.type,
    required this.analysisStatus,
    this.mimeType,
    this.analysis,
    this.error,
  });

  final String name;
  final String path;
  final NovaAttachmentType type;
  final NovaAttachmentAnalysisStatus analysisStatus;
  final String? mimeType;
  final Map<String, dynamic>? analysis;
  final String? error;

  NovaAttachment copyWith({
    NovaAttachmentAnalysisStatus? analysisStatus,
    String? mimeType,
    Map<String, dynamic>? analysis,
    String? error,
  }) => NovaAttachment(
    name: name,
    path: path,
    type: type,
    analysisStatus: analysisStatus ?? this.analysisStatus,
    mimeType: mimeType ?? this.mimeType,
    analysis: analysis ?? this.analysis,
    error: error ?? this.error,
  );

  Map<String, dynamic> toAgentInput() => {
    'type': type.name,
    'name': name,
    if (mimeType != null) 'mimeType': mimeType,
    'analysisStatus': analysisStatus.name,
    if (analysis != null) 'analysis': analysis,
    if (error != null) 'error': error,
  };
}
