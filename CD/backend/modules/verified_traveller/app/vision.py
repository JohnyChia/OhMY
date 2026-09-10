from dataclasses import dataclass
from datetime import date, datetime
from difflib import SequenceMatcher
import re

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


@dataclass(frozen=True)
class _OcrSample:
    text: str
    document: np.ndarray


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

    def detect_one(
        self,
        image: np.ndarray,
        score_threshold: float = 0.8,
        require_exactly_one: bool = True,
    ) -> np.ndarray:
        height, width = image.shape[:2]
        self.detector.setScoreThreshold(score_threshold)
        self.detector.setInputSize((width, height))
        _, faces = self.detector.detect(image)
        if faces is None or len(faces) == 0:
            raise CheckFailure(
                "face_count",
                "Make sure a clear face is visible in the photo.",
            )
        if require_exactly_one and len(faces) != 1:
            raise CheckFailure(
                "face_count",
                "Make sure exactly one clear face is visible in the selfie.",
            )
        return max(faces, key=lambda face: float(face[2] * face[3]))

    def crop_portrait(self, image: np.ndarray) -> np.ndarray:
        face = self.detect_one(
            image,
            score_threshold=0.45,
            require_exactly_one=False,
        )
        x, y, width, height = face[:4].astype(int)
        margin_x, margin_y = int(width * 0.35), int(height * 0.35)
        return image[
            max(0, y - margin_y) : min(image.shape[0], y + height + margin_y),
            max(0, x - margin_x) : min(image.shape[1], x + width + margin_x),
        ]

    def similarity(self, document_face: np.ndarray, selfie: np.ndarray) -> float:
        doc_face = self.detect_one(
            document_face,
            score_threshold=0.45,
            require_exactly_one=False,
        )
        selfie_face = self.detect_one(selfie, score_threshold=0.8)
        doc_aligned = self.recognizer.alignCrop(document_face, doc_face)
        selfie_aligned = self.recognizer.alignCrop(selfie, selfie_face)
        doc_feature = self.recognizer.feature(doc_aligned)
        selfie_feature = self.recognizer.feature(selfie_aligned)
        return float(
            self.recognizer.match(
                doc_feature, selfie_feature, cv2.FaceRecognizerSF_FR_COSINE
            )
        )

def _order_corners(points: np.ndarray) -> np.ndarray:
    ordered = np.zeros((4, 2), dtype=np.float32)
    sums = points.sum(axis=1)
    differences = np.diff(points, axis=1).reshape(-1)
    ordered[0] = points[np.argmin(sums)]
    ordered[2] = points[np.argmax(sums)]
    ordered[1] = points[np.argmin(differences)]
    ordered[3] = points[np.argmax(differences)]
    return ordered


def _warp_document(image: np.ndarray, corners: np.ndarray) -> np.ndarray:
    top_left, top_right, bottom_right, bottom_left = _order_corners(corners)
    width = int(
        max(
            np.linalg.norm(bottom_right - bottom_left),
            np.linalg.norm(top_right - top_left),
        )
    )
    height = int(
        max(
            np.linalg.norm(top_right - bottom_right),
            np.linalg.norm(top_left - bottom_left),
        )
    )
    if width < 320 or height < 200:
        return image
    target = np.array(
        [[0, 0], [width - 1, 0], [width - 1, height - 1], [0, height - 1]],
        dtype=np.float32,
    )
    matrix = cv2.getPerspectiveTransform(
        np.array([top_left, top_right, bottom_right, bottom_left]),
        target,
    )
    return cv2.warpPerspective(image, matrix, (width, height))


def _perspective_candidate(image: np.ndarray) -> np.ndarray | None:
    height, width = image.shape[:2]
    scale = min(1.0, 1400.0 / max(height, width))
    preview = cv2.resize(
        image,
        None,
        fx=scale,
        fy=scale,
        interpolation=cv2.INTER_AREA,
    )
    gray = cv2.cvtColor(preview, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(gray, 45, 140)
    edges = cv2.morphologyEx(
        edges,
        cv2.MORPH_CLOSE,
        cv2.getStructuringElement(cv2.MORPH_RECT, (9, 9)),
    )
    contours, _ = cv2.findContours(
        edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE
    )
    frame_area = preview.shape[0] * preview.shape[1]
    for contour in sorted(contours, key=cv2.contourArea, reverse=True)[:20]:
        area = cv2.contourArea(contour)
        if area < frame_area * 0.12 or area > frame_area * 0.98:
            continue
        perimeter = cv2.arcLength(contour, True)
        polygon = cv2.approxPolyDP(contour, 0.025 * perimeter, True)
        if len(polygon) != 4 or not cv2.isContourConvex(polygon):
            continue
        corners = polygon.reshape(4, 2).astype(np.float32) / scale
        ordered = _order_corners(corners)
        candidate_width = max(
            np.linalg.norm(ordered[1] - ordered[0]),
            np.linalg.norm(ordered[2] - ordered[3]),
        )
        candidate_height = max(
            np.linalg.norm(ordered[3] - ordered[0]),
            np.linalg.norm(ordered[2] - ordered[1]),
        )
        short_side = min(candidate_width, candidate_height)
        long_side = max(candidate_width, candidate_height)
        if short_side == 0 or not 1.15 <= long_side / short_side <= 2.05:
            continue
        return _warp_document(image, corners)
    return None


def _content_band_candidate(image: np.ndarray) -> np.ndarray | None:
    height, width = image.shape[:2]
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    saturation = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)[:, :, 1]
    row_activity = (
        (gray.std(axis=1) > 18) | (saturation.mean(axis=1) > 28)
    ).astype(np.uint8)
    kernel_height = max(17, height // 35)
    connected = cv2.morphologyEx(
        row_activity.reshape(-1, 1),
        cv2.MORPH_CLOSE,
        cv2.getStructuringElement(cv2.MORPH_RECT, (1, kernel_height)),
    )
    contours, _ = cv2.findContours(
        connected, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
    )
    if not contours:
        return None
    _, y, _, band_height = max(
        (cv2.boundingRect(contour) for contour in contours),
        key=lambda bounds: bounds[3],
    )
    if band_height < height * 0.18 or band_height > height * 0.96:
        return None
    margin = max(8, int(height * 0.025))
    top = max(0, y - margin)
    bottom = min(height, y + band_height + margin)
    candidate = image[top:bottom, 0:width]
    return candidate if candidate.size else None


def _blue_document_candidate(image: np.ndarray) -> np.ndarray | None:
    height, width = image.shape[:2]
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    blue_mask = cv2.inRange(
        hsv,
        np.array([72, 25, 70], dtype=np.uint8),
        np.array([118, 255, 255], dtype=np.uint8),
    )
    kernel_size = max(11, int(min(height, width) * 0.035))
    if kernel_size % 2 == 0:
        kernel_size += 1
    blue_mask = cv2.morphologyEx(
        blue_mask,
        cv2.MORPH_CLOSE,
        cv2.getStructuringElement(
            cv2.MORPH_RECT, (kernel_size, kernel_size)
        ),
    )
    contours, _ = cv2.findContours(
        blue_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
    )
    frame_area = height * width
    for contour in sorted(contours, key=cv2.contourArea, reverse=True):
        x, y, candidate_width, candidate_height = cv2.boundingRect(contour)
        bounds_area = candidate_width * candidate_height
        if bounds_area < frame_area * 0.08:
            continue
        ratio = candidate_width / max(1, candidate_height)
        if not 1.05 <= ratio <= 2.4:
            continue
        margin_x = int(candidate_width * 0.035)
        margin_y = int(candidate_height * 0.055)
        left = max(0, x - margin_x)
        top = max(0, y - margin_y)
        right = min(width, x + candidate_width + margin_x)
        bottom = min(height, y + candidate_height + margin_y)
        candidate = image[top:bottom, left:right]
        return candidate if candidate.size else None
    return None


def _document_candidates(image: np.ndarray) -> list[np.ndarray]:
    candidates = [image]
    for candidate in (
        _perspective_candidate(image),
        _content_band_candidate(image),
        _blue_document_candidate(image),
    ):
        if candidate is None:
            continue
        if any(
            abs(candidate.shape[0] - existing.shape[0]) < 8
            and abs(candidate.shape[1] - existing.shape[1]) < 8
            for existing in candidates
        ):
            continue
        candidates.append(candidate)
    return candidates


def _enhance_for_ocr(image: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    target_width = 1500
    scale = min(3.0, max(1.25, target_width / max(1, gray.shape[1])))
    gray = cv2.resize(
        gray,
        None,
        fx=scale,
        fy=scale,
        interpolation=cv2.INTER_CUBIC,
    )
    contrast = cv2.createCLAHE(clipLimit=2.2, tileGridSize=(8, 8)).apply(gray)
    blurred = cv2.GaussianBlur(contrast, (0, 0), 1.2)
    sharpened = cv2.addWeighted(contrast, 1.7, blurred, -0.7, 0)
    thresholded = cv2.adaptiveThreshold(
        contrast,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        35,
        11,
    )
    return sharpened, thresholded


def _read_text(
    image: np.ndarray,
    config: str,
) -> str:
    try:
        return pytesseract.image_to_string(image, config=config).upper()
    except pytesseract.TesseractNotFoundError as error:
        raise RuntimeError(
            "Tesseract OCR is not installed or TESSERACT_CMD is incorrect."
        ) from error


def _ocr_samples(
    image: np.ndarray,
    settings: Settings,
    include_mrz: bool = False,
) -> list[_OcrSample]:
    if settings.tesseract_cmd:
        pytesseract.pytesseract.tesseract_cmd = settings.tesseract_cmd
    samples: list[_OcrSample] = []
    for document in _document_candidates(image):
        sharpened, thresholded = _enhance_for_ocr(document)
        for processed, config in (
            (sharpened, "--oem 3 --psm 6"),
            (thresholded, "--oem 3 --psm 11"),
        ):
            text = _read_text(processed, config)
            if text.strip():
                samples.append(_OcrSample(text=text, document=document))
        if include_mrz:
            mrz_top = max(0, int(document.shape[0] * 0.55))
            mrz_region = document[mrz_top:, :]
            mrz_gray, _ = _enhance_for_ocr(mrz_region)
            mrz_text = _read_text(
                mrz_gray,
                "--oem 3 --psm 6 "
                "-c tessedit_char_whitelist=ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<",
            )
            if mrz_text.strip():
                samples.append(_OcrSample(text=mrz_text, document=document))
    return samples


def _contains_mykad_marker(samples: list[_OcrSample]) -> bool:
    expected_words = ("MALAYSIA", "MYKAD")
    expected_phrases = ("KADPENGENALAN", "IDENTITYCARD")
    for sample in samples:
        compact = re.sub(r"[^A-Z0-9]", "", sample.text)
        if any(phrase in compact for phrase in expected_phrases):
            return True
        words = re.findall(r"[A-Z]{4,12}", sample.text)
        for word in words:
            if any(
                expected in word
                or SequenceMatcher(None, word, expected).ratio() >= 0.72
                for expected in expected_words
            ):
                return True
    return False


def _extract_mykad_identifier(
    samples: list[_OcrSample],
) -> tuple[str, np.ndarray] | None:
    separated_pattern = re.compile(
        r"(?<!\d)(\d{6})\s*[-–—./]?\s*(\d{2})"
        r"\s*[-–—./]?\s*(\d{4})(?!\d)"
    )
    for sample in samples:
        for line in sample.text.splitlines():
            match = separated_pattern.search(line)
            if match:
                return "".join(match.groups()), sample.document
            line_digits = re.sub(r"\D", "", line)
            if len(line_digits) == 12:
                return line_digits, sample.document
    for sample in samples:
        digits = re.sub(r"\D", "", sample.text)
        match = re.search(r"\d{12}", digits)
        if match:
            return match.group(0), sample.document
    return None


def _clean_mrz_line(line: str) -> str:
    return re.sub(r"[^A-Z0-9<]", "", line.upper())


def _numeric_mrz_field(value: str) -> str:
    common_ocr_mistakes = {
        "O": "0",
        "Q": "0",
        "I": "1",
        "L": "1",
        "S": "5",
        "B": "8",
    }
    return value.translate(str.maketrans(common_ocr_mistakes))


def _extract_passport_identifier(
    samples: list[_OcrSample],
) -> tuple[str, str, np.ndarray] | None:
    for sample in samples:
        lines = [
            _clean_mrz_line(line)
            for line in sample.text.splitlines()
            if len(_clean_mrz_line(line)) >= 27
        ]
        for index, line in enumerate(lines):
            if not (
                line.startswith("P<")
                or (line.startswith("P") and len(line) >= 35)
            ):
                continue
            following = lines[index + 1 :]
            passport_line = next(
                (
                    candidate
                    for candidate in following
                    if sum(character.isdigit() for character in candidate) >= 10
                ),
                None,
            )
            if passport_line is None or len(passport_line) < 27:
                continue
            identifier = passport_line[:9].replace("<", "")
            birth_date = _numeric_mrz_field(passport_line[13:19])
            expiry = _numeric_mrz_field(passport_line[21:27])
            if (
                len(identifier) >= 5
                and birth_date.isdigit()
                and expiry.isdigit()
            ):
                return identifier, expiry, sample.document
    return None


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

    if document_type == "mykad":
        samples = _ocr_samples(front, settings)
        extracted = _extract_mykad_identifier(samples)
        if extracted is None or not _contains_mykad_marker(samples):
            raise CheckFailure(
                "invalid_mykad",
                "We could not read the MyKad heading and identification number. "
                "Fill the frame with the card, avoid glare, and try again.",
            )
        identifier, document_image = extracted
        document_image = min(
            (sample.document for sample in samples),
            key=lambda candidate: candidate.shape[0] * candidate.shape[1],
        )
    elif document_type == "passport":
        samples = _ocr_samples(front, settings, include_mrz=True)
        extracted = _extract_passport_identifier(samples)
        if extracted is None:
            raise CheckFailure(
                "invalid_passport",
                "The passport machine-readable lines could not be read. "
                "Keep the full biodata page visible, avoid glare, and try again.",
            )
        identifier, expiry_raw, document_image = extracted
        if expiry_raw.isdigit():
            try:
                expiry = _parse_mrz_date(expiry_raw)
                if expiry < date.today():
                    raise CheckFailure(
                        "expired_passport",
                        "This passport is expired. Use a valid passport.",
                        retryable=False,
                    )
            except ValueError:
                pass
    else:
        raise CheckFailure("document_type", "Choose MyKad or Passport.")

    portrait = faces.crop_portrait(document_image)
    return DocumentCheck(identifier=identifier, portrait=portrait)


def _parse_mrz_date(value: str) -> date:
    year = int(value[:2])
    current_two_digit_year = date.today().year % 100
    century = 2000 if year <= current_two_digit_year + 20 else 1900
    return datetime.strptime(f"{century + year}{value[2:]}", "%Y%m%d").date()
