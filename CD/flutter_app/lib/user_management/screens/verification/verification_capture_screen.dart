import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/wau_loading_indicator.dart';
import 'package:flutter_app/shared/widgets/ohmy_snack_bar.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/verification_result.dart';
import '../../services/verification_service.dart';

enum _DocumentType { mykad, passport }

class VerificationCaptureScreen extends StatefulWidget {
  const VerificationCaptureScreen({super.key});

  @override
  State<VerificationCaptureScreen> createState() =>
      _VerificationCaptureScreenState();
}

class _VerificationCaptureScreenState extends State<VerificationCaptureScreen> {
  final _imagePicker = ImagePicker();
  CameraController? _camera;
  _DocumentType _documentType = _DocumentType.mykad;
  String? _frontPath;
  String? _backPath;
  bool _capturingBackSide = false;
  bool _capturing = false;
  String? _cameraError;

  bool get _needsBack => _documentType == _DocumentType.mykad;
  bool get _capturingBack => _needsBack && _capturingBackSide;
  String? get _currentPath => _capturingBack ? _backPath : _frontPath;

  @override
  void initState() {
    super.initState();
    _openCamera();
  }

  Future<void> _openCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('none', 'No camera');
      final rear = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        rear,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } on CameraException {
      if (mounted) {
        setState(() {
          _cameraError =
              'The camera could not be opened. Allow camera permission and try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  void _changeType(_DocumentType type) {
    if (_capturing || type == _documentType) return;
    setState(() {
      _documentType = type;
      _frontPath = null;
      _backPath = null;
      _capturingBackSide = false;
    });
  }

  Future<void> _takePhoto() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final image = await camera.takePicture();
      if (!mounted) return;
      setState(() {
        if (_capturingBack) {
          _backPath = image.path;
        } else {
          _frontPath = image.path;
        }
      });
    } on CameraException {
      _showMessage('The photo could not be captured. Please try again.');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _pickDocumentPhoto() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (!mounted || image == null) return;
      setState(() {
        if (_capturingBack) {
          _backPath = image.path;
        } else {
          _frontPath = image.path;
        }
      });
    } catch (_) {
      _showMessage('The selected image could not be opened. Try another one.');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _retake() {
    setState(() {
      if (_capturingBack) {
        _backPath = null;
      } else {
        _frontPath = null;
      }
    });
  }

  Future<void> _continue() async {
    if (_frontPath == null) return;
    if (_needsBack && _backPath == null) {
      setState(() {});
      return;
    }

    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _SelfieVerificationScreen(
          documentType: _documentType.name,
          documentFrontPath: _frontPath!,
          documentBackPath: _backPath,
        ),
      ),
    );
    if (!mounted) return;
    if (verified == true) {
      Navigator.of(context).pop(true);
    } else if (verified == false) {
      setState(() {
        _frontPath = null;
        _backPath = null;
        _capturingBackSide = false;
      });
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(OhMySnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = _currentPath;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          children: [
            _VerificationHeader(
              backLabel: 'Back',
              progress: 'STEP 1 OF 2',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            const Text(
              'Photograph your ID',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF17243D), fontSize: 28),
            ),
            const SizedBox(height: 8),
            const Text(
              'Capture your document with the camera or upload a clear photo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF62708A), fontSize: 13),
            ),
            const SizedBox(height: 18),
            _DocumentTypeSelector(
              selected: _documentType,
              onChanged: _changeType,
            ),
            const SizedBox(height: 22),
            Text(
              _capturingBack
                  ? 'MYKAD — BACK'
                  : (_documentType == _DocumentType.mykad
                        ? 'MYKAD — FRONT'
                        : 'PASSPORT — BIODATA PAGE'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF2E60C4),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _DocumentCameraPanel(
              controller: _camera,
              capturedPath: currentPath,
              error: _cameraError,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F7FE),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Privacy: photos are sent only to your laptop verification service. Successful verification photos are deleted after processing.',
                style: TextStyle(color: Color(0xFF536681), fontSize: 11),
              ),
            ),
            const SizedBox(height: 16),
            if (currentPath == null)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _capturing ? null : _pickDocumentPhoto,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Upload photo'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _cameraError == null && !_capturing
                          ? _takePhoto
                          : null,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(_capturing ? 'Opening…' : 'Use camera'),
                    ),
                  ),
                ],
              )
            else ...[
              OutlinedButton(onPressed: _retake, child: const Text('Retake')),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _capturingBack || !_needsBack
                    ? _continue
                    : () {
                        setState(() => _capturingBackSide = true);
                      },
                child: Text(
                  _needsBack && !_capturingBack
                      ? 'Continue to MyKad back'
                      : 'Continue to selfie',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SelfieVerificationScreen extends StatefulWidget {
  const _SelfieVerificationScreen({
    required this.documentType,
    required this.documentFrontPath,
    this.documentBackPath,
  });

  final String documentType;
  final String documentFrontPath;
  final String? documentBackPath;

  @override
  State<_SelfieVerificationScreen> createState() =>
      _SelfieVerificationScreenState();
}

class _SelfieVerificationScreenState extends State<_SelfieVerificationScreen> {
  final _service = VerificationService();
  CameraController? _camera;
  bool _busy = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    _openCamera();
  }

  Future<void> _openCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return controller.dispose();
      setState(() => _camera = controller);
    } on CameraException {
      if (mounted) {
        setState(() {
          _cameraError =
              'The front camera could not be opened. Check camera permission.';
        });
      }
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _captureAndVerify() async {
    final camera = _camera;
    if (_busy || camera == null || !camera.value.isInitialized) return;
    setState(() => _busy = true);
    try {
      final image = await camera.takePicture();
      if (!mounted) return;
      final result = await _service.submit(
        documentType: widget.documentType,
        documentFrontPath: widget.documentFrontPath,
        documentBackPath: widget.documentBackPath,
        selfiePath: image.path,
      );
      if (result.verified) await _service.refreshVerifiedSession();
      if (!mounted) return;
      final completed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => _VerificationResultScreen(result: result),
        ),
      );
      if (!mounted) return;
      if (completed == true) {
        Navigator.of(context).pop(true);
      } else if (!result.verified) {
        // Return false to step 1 so a failed attempt always starts again with
        // the document front, rather than reusing an earlier document photo.
        Navigator.of(context).pop(false);
      }
    } on CameraException {
      _showMessage('The selfie could not be captured. Please try again.');
    } on VerificationFailure catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      OhMySnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          children: [
            _VerificationHeader(
              backLabel: 'Back',
              progress: 'STEP 2 OF 2',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            const Text(
              'Take a live selfie',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF17243D), fontSize: 28),
            ),
            const SizedBox(height: 8),
            const Text(
              'Look straight at the camera. Your selfie will be submitted immediately after capture.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF62708A), fontSize: 13),
            ),
            const SizedBox(height: 22),
            _SelfieCameraPanel(
              controller: _camera,
              capturedPath: null,
              error: _cameraError,
              instruction: 'Keep your face centred and look straight ahead',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F7FE),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Face matching compares this live front selfie with the portrait on your document.',
                style: TextStyle(color: Color(0xFF536681), fontSize: 11),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _busy || _cameraError != null
                  ? null
                  : _captureAndVerify,
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(_busy ? 'Verifying…' : 'Capture and verify'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationResultScreen extends StatelessWidget {
  const _VerificationResultScreen({required this.result});

  final VerificationResult result;

  @override
  Widget build(BuildContext context) {
    final verified = result.verified;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  color: verified
                      ? const Color(0xFFE5F2FF)
                      : const Color(0xFFFFEEEE),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  verified ? Icons.verified_user : Icons.error_outline,
                  size: 64,
                  color: verified
                      ? const Color(0xFF2E60C4)
                      : const Color(0xFFB42318),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                verified ? 'Identity verified' : 'We couldn’t verify you',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF17243D), fontSize: 28),
              ),
              const SizedBox(height: 12),
              Text(
                result.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF62708A),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 36),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(verified),
                child: Text(verified ? 'Return to profile' : 'Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerificationHeader extends StatelessWidget {
  const _VerificationHeader({
    required this.backLabel,
    required this.progress,
    required this.onBack,
  });

  final String backLabel;
  final String progress;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: backLabel,
          onPressed: onBack,
          padding: EdgeInsets.zero,
          alignment: Alignment.centerLeft,
          icon: const Icon(Icons.arrow_back),
        ),
        const Spacer(),
        Text(
          progress,
          style: const TextStyle(color: Color(0xFF2E60C4), fontSize: 11),
        ),
      ],
    );
  }
}

class _DocumentTypeSelector extends StatelessWidget {
  const _DocumentTypeSelector({
    required this.selected,
    required this.onChanged,
  });

  final _DocumentType selected;
  final ValueChanged<_DocumentType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF3FB),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: _DocumentType.values.map((type) {
          final active = type == selected;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onChanged(type),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: active
                      ? const [
                          BoxShadow(color: Color(0x18000000), blurRadius: 4),
                        ]
                      : null,
                ),
                child: Text(
                  type == _DocumentType.mykad ? 'MyKad' : 'Passport',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: active
                        ? const Color(0xFF2E60C4)
                        : const Color(0xFF62708A),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DocumentCameraPanel extends StatelessWidget {
  const _DocumentCameraPanel({
    required this.controller,
    required this.capturedPath,
    required this.error,
  });

  final CameraController? controller;
  final String? capturedPath;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 332,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF18243A),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (capturedPath != null)
            Image.file(File(capturedPath!), fit: BoxFit.cover)
          else if (controller?.value.isInitialized == true)
            _ProportionalCameraPreview(controller: controller!)
          else
            Center(
              child: error == null
                  ? const WauLoadingIndicator(size: 58)
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
            ),
          if (capturedPath == null && error == null)
            Center(
              child: Container(
                width: 296,
                height: 187,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          if (capturedPath == null && error == null)
            const Positioned(
              left: 24,
              right: 24,
              bottom: 18,
              child: Text(
                'Keep all edges visible and avoid glare',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _SelfieCameraPanel extends StatelessWidget {
  const _SelfieCameraPanel({
    required this.controller,
    required this.capturedPath,
    required this.error,
    required this.instruction,
  });

  final CameraController? controller;
  final String? capturedPath;
  final String? error;
  final String instruction;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 385,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF18243A),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (capturedPath != null)
            Image.file(File(capturedPath!), fit: BoxFit.cover)
          else if (controller?.value.isInitialized == true)
            _ProportionalCameraPreview(
              controller: controller!,
              unmirrorFrontCamera: true,
            )
          else
            Center(
              child: error == null
                  ? const WauLoadingIndicator(size: 58)
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
            ),
          Center(
            child: Container(
              width: 180,
              height: 230,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: const BorderRadius.all(
                  Radius.elliptical(90, 115),
                ),
              ),
            ),
          ),
          Positioned(
            left: 26,
            right: 26,
            bottom: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xAA10192B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                instruction,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProportionalCameraPreview extends StatelessWidget {
  const _ProportionalCameraPreview({
    required this.controller,
    this.unmirrorFrontCamera = false,
  });

  final CameraController controller;
  final bool unmirrorFrontCamera;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return const SizedBox.shrink();

    // Camera preview sizes are reported in the sensor's landscape orientation.
    // Give FittedBox the rotated dimensions so it can crop without stretching.
    Widget preview = SizedBox(
      width: previewSize.height,
      height: previewSize.width,
      child: CameraPreview(controller),
    );

    if (unmirrorFrontCamera &&
        controller.description.lensDirection == CameraLensDirection.front) {
      preview = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1, 1, 1),
        child: preview,
      );
    }

    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          clipBehavior: Clip.hardEdge,
          child: preview,
        ),
      ),
    );
  }
}
