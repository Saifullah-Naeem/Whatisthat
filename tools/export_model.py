"""Export YOLOv8n Open Images V7 (601 classes) to ONNX (416x416) and extract labels."""

from pathlib import Path
import shutil
import tempfile
import numpy as np
import onnxruntime as ort
from ultralytics import YOLO


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    out_dir = repo_root / "assets" / "models"
    out_dir.mkdir(parents=True, exist_ok=True)

    onnx_target = out_dir / "yolov8n_oiv7_416.onnx"
    labels_target = out_dir / "oiv7_labels.txt"

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        pt_path = tmp_path / "yolov8n-oiv7.pt"
        model = YOLO(str(pt_path))

        # Write ordered 601 Open Images V7 labels
        names = model.names
        ordered_labels = [names[i] for i in range(len(names))]
        labels_target.write_text("\n".join(ordered_labels) + "\n", encoding="utf-8")
        print(f"Wrote {len(ordered_labels)} labels to {labels_target}")

        # Export to ONNX at 416x416 for fast, low-latency desktop & mobile inference
        exported_path = Path(
            model.export(
                format="onnx",
                imgsz=416,
                simplify=True,
                dynamic=False,
                opset=17,
            )
        )
        shutil.copy2(exported_path, onnx_target)
        print(f"Copied ONNX model ({onnx_target.stat().st_size / (1024 * 1024):.2f} MB) to {onnx_target}")

    # Verify ONNX input/output contract with onnxruntime
    sess = ort.InferenceSession(str(onnx_target), providers=["CPUExecutionProvider"])
    inp = sess.get_inputs()[0]
    out = sess.get_outputs()[0]
    dummy = np.zeros((1, 3, 416, 416), dtype=np.float32)
    res = sess.run([out.name], {inp.name: dummy})[0]
    print(f"Input:  name={inp.name!r}, shape={inp.shape}, type={inp.type}")
    print(f"Output: name={out.name!r}, shape={out.shape}, runtime_shape={res.shape}")


if __name__ == "__main__":
    main()
