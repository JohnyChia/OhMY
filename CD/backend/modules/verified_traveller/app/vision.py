import re
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path

import cv2
import numpy as np
import pytesseract

from .config import BASE_DIR, Settings


class CheckFailure(Exception):
    def __init__(self, code: str, message: str, retryable: bool = True):
        super().__init__(message)
        self.code = code
        self.message = message
        self.retryable = retryable


@dataclass(frozen=True)
class DocumentCheck:
    identifier: str
    portrait: np.ndarray


def decode_image(data: bytes) -> np.ndarray:
    image = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise CheckFailure("invalid_image", "The photo could not be read.")
    return image


def check_image_quality(image: np.ndarray) -> None:
    height, width = image.shape[:2]
    if min(height, width) < 480:
        raise CheckFailure(
            "low_resolution",
            "The photo is too small. Move closer and retake it.",
        )
    sharpness = cv2.Laplacian(
        cv2.cvtColor(image, cv2.COLOR_BGR2GRAY), cv2.CV_64F
    ).var()
    if sharpness < 45:
        raise CheckFailure(
            "blurred_document",
            "The document photo is blurry. Hold the camera steady and retake it.",
        )


class FaceEngine:
    def __init__(self, settings: Settings):
        model_dir = BASE_DIR / "models"
        detector_path = model_dir / "face_detection_yunet_2023mar.onnx"
        recognizer_path = model_dir / "face_recognition_sface_2021dec.onnx"
        if not detector_path.exists() or not recognizer_path.exists():
            raise RuntimeError("Face models are missing. Run: python setup_models.py")
        self.detector = cv2.FaceDetectorYN.create(
            str(detector_path), "", (320, 320), 0.8, 0.3, 5000
        )
        self.recognizer = cv2.FaceRecognizerSF.create(str(recognizer_path), "")
        self.threshold = settings.face_match_threshold

    def detect_one(self, image: np.ndarray) -> np.ndarray:
        height, width = image.shape[:2]
        self.detector.setInputSize((width, height))
        _, faces = self.detector.detect(image)
        if faces is None or len(faces) != 1:
            raise CheckFailure(
                "face_count",
                "Make sure exactly one clear face is visible in the photo.",
            )
        return faces[0]

    def crop_portrait(self, image: np.ndarray) -> np.ndarray:
        face = self.detect_one(image)
        x, y, width, height = face[:4].astype(int)
        margin_x, margin_y = int(width * 0.35), int(height * 0.35)
        return image[
            max(0, y - margin_y) : min(image.shape[0], y + height + margin_y),
            max(0, x - margin_x) : min(image.shape[1], x + width + margin_x),
        ]

    def similarity(self, document_face: np.ndarray, selfie: np.ndarray) -> float:
        doc_face = self.detect_one(document_face)
        selfie_face = self.detect_one(selfie)
        doc_aligned = self.recognizer.alignCrop(document_face, doc_face)
        selfie_aligned = self.recognizer.alignCrop(selfie, selfie_face)
        doc_feature = self.recognizer.feature(doc_aligned)
        selfie_feature = self.recognizer.feature(selfie_aligned)
        return float(
            self.recognizer.match(
                doc_feature, selfie_feature, cv2.FaceRecognizerSF_FR_COSINE
            )
        )

    def pose_offset(self, image: np.ndarray) -> float:
        face = self.detect_one(image)
        # YuNet returns five landmarks after the bounding box. The first two
        # are the eyes and the third is the nose tip.
        first_eye_x = float(face[4])
        second_eye_x = float(face[6])
        nose_x = float(face[8])
        eye_width = max(abs(second_eye_x - first_eye_x), 1.0)
        return (nose_x - ((first_eye_x + second_eye_x) / 2)) / eye_width


def _ocr(image: np.ndarray, settings: Settings) -> str:
    if settings.tesseract_cmd:
        pytesseract.pytesseract.tesseract_cmd = settings.tesseract_cmd
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    gray = cv2.resize(gray, None, fx=1.5, fy=1.5, interpolation=cv2.INTER_CUBIC)
    try:
        return pytesseract.image_to_string(gray, config="--psm 6").upper()
    except pytesseract.TesseractNotFoundError as error:
        raise RuntimeError(
            "Tesseract OCR is not installed or TESSERACT_CMD is incorrect."
        ) from error


def inspect_document(
    document_type: str,
    front: np.ndarray,
    back: np.ndarray | None,
    settings: Settings,
    faces: FaceEngine,
) -> DocumentCheck:
    check_image_quality(front)
    if document_type == "mykad" and back is None:
        raise CheckFailure("missing_back", "Capture both sides of the MyKad.")
    if back is not None:
        check_image_quality(back)

    text = _ocr(front, settings)
    compact = re.sub(r"[^A-Z0-9<]", "", text)
    if document_type == "mykad":
        digits = re.sub(r"\D", "", text)
        match = re.search(r"\d{12}", digits)
        if not match or "MALAYSIA" not in text:
            raise CheckFailure(
                "invalid_mykad",
                "This does not look like a Malaysian MyKad. Retake a clear front photo.",
            )
        identifier = match.group(0)
    elif document_type == "passport":
        mrz_lines = [
            re.sub(r"[^A-Z0-9<]", "", line)
            for line in text.splitlines()
            if len(re.sub(r"[^A-Z0-9<]", "", line)) >= 30
        ]
        header_index = next(
            (index for index, line in enumerate(mrz_lines) if line.startswith("P<")),
            None,
        )
        passport_line = (
            mrz_lines[header_index + 1]
            if header_index is not None and header_index + 1 < len(mrz_lines)
            else None
        )
        if passport_line is None:
            raise CheckFailure(
                "invalid_passport",
                "The passport biodata page could not be read. Avoid glare and retake it.",
            )
        identifier = passport_line[:9].replace("<", "")
        expiry_raw = passport_line[21:27]
        if expiry_raw.isdigit():
            expiry = _parse_mrz_date(expiry_raw)
            if expiry < date.today():
                raise CheckFailure(
                    "expired_passport",
                    "This passport is expired. Use a valid passport.",
                    retryable=False,
                )
    else:
        raise CheckFailure("document_type", "Choose MyKad or Passport.")

    portrait = faces.crop_portrait(front)
    return DocumentCheck(identifier=identifier, portrait=portrait)


def _parse_mrz_date(value: str) -> date:
    year = int(value[:2])
    current_two_digit_year = date.today().year % 100
    century = 2000 if year <= current_two_digit_year + 20 else 1900
    return datetime.strptime(f"{century + year}{value[2:]}", "%Y%m%d").date()


def check_head_turns(
    center: np.ndarray,
    left: np.ndarray,
    right: np.ndarray,
    faces: FaceEngine,
) -> None:
    positions = [faces.pose_offset(image) for image in (center, left, right)]
    center_offset, first_turn, second_turn = positions
    if abs(center_offset) > 0.13:
        raise CheckFailure(
            "centre_pose",
            "Look straight at the camera for the first selfie.",
        )
    # Front-camera image mirroring differs between devices, so require two
    # clearly opposite turns without assuming which saved image is mirrored.
    if first_turn * second_turn >= 0 or abs(first_turn) < 0.08 or abs(second_turn) < 0.08:
        raise CheckFailure(
            "head_turn",
            "The head-turn check was not clear. Turn left and right more slowly.",
        )
