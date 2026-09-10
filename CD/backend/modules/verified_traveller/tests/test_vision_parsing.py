import unittest

import numpy as np

from app.vision import (
    _OcrSample,
    _contains_mykad_marker,
    _extract_mykad_identifier,
    _extract_passport_identifier,
)


class VisionParsingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.document = np.zeros((600, 950, 3), dtype=np.uint8)

    def test_mykad_accepts_identity_card_marker_and_formatted_number(self) -> None:
        samples = [
            _OcrSample(
                text="KAD PENGENALAN MALAYSIA\n020228-00-1010",
                document=self.document,
            )
        ]

        extracted = _extract_mykad_identifier(samples)

        self.assertTrue(_contains_mykad_marker(samples))
        self.assertIsNotNone(extracted)
        self.assertEqual(extracted[0], "020228001010")

    def test_passport_skips_noisy_mrz_and_uses_structured_line(self) -> None:
        samples = [
            _OcrSample(
                text=(
                    "P<KORPARK<<MIN<JUN<<<<<<<<<<<<<<<<<<<<<<<<<\n"
                    "NOISY12345<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"
                ),
                document=self.document,
            ),
            _OcrSample(
                text=(
                    "P<KORPARK<<MIN<JUN<<<<<<<<<<<<<<<<<<<<<<<<<\n"
                    "KOR6543215KOR9503157M3001019<<<<<<<<<<<<<<06"
                ),
                document=self.document,
            ),
        ]

        extracted = _extract_passport_identifier(samples)

        self.assertIsNotNone(extracted)
        self.assertEqual(extracted[0], "KOR654321")
        self.assertEqual(extracted[1], "300101")


if __name__ == "__main__":
    unittest.main()
