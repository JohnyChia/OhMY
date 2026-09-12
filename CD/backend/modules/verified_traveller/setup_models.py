from pathlib import Path
from urllib.request import urlretrieve


MODELS = {
    "face_detection_yunet_2023mar.onnx": (
        "https://github.com/opencv/opencv_zoo/raw/main/models/"
        "face_detection_yunet/face_detection_yunet_2023mar.onnx"
    ),
    "face_recognition_sface_2021dec.onnx": (
        "https://github.com/opencv/opencv_zoo/raw/main/models/"
        "face_recognition_sface/face_recognition_sface_2021dec.onnx"
    ),
}


def main() -> None:
    model_dir = Path(__file__).parent / "models"
    model_dir.mkdir(exist_ok=True)
    for name, url in MODELS.items():
        target = model_dir / name
        if target.exists():
            print(f"Already present: {target}")
            continue
        print(f"Downloading {name}...")
        urlretrieve(url, target)
    print("Model setup complete.")


if __name__ == "__main__":
    main()
