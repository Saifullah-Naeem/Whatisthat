"""Verify exported ONNX model on a desk workspace photo and local webcam stream."""

import json
from pathlib import Path
import time
import cv2
import numpy as np
import onnxruntime as ort


def letterbox_and_run(
    sess: ort.InferenceSession,
    labels: list[str],
    bgr_img: np.ndarray,
    conf_thresh: float = 0.30,
) -> tuple[list[dict], float]:
    h, w = bgr_img.shape[:2]
    size = 416
    scale = min(size / w, size / h)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    pad_x, pad_y = (size - nw) // 2, (size - nh) // 2

    resized = cv2.resize(bgr_img, (nw, nh), interpolation=cv2.INTER_LINEAR)
    canvas = np.full((size, size, 3), 114, dtype=np.uint8)
    canvas[pad_y : pad_y + nh, pad_x : pad_x + nw] = resized
    rgb = cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
    inp = np.transpose(rgb, (2, 0, 1))[None, ...]

    t0 = time.perf_counter()
    out = sess.run(["output0"], {"images": inp})[0][0]  # (605, 3549)
    infer_ms = (time.perf_counter() - t0) * 1000.0

    scores = out[4:]
    cls_ids = np.argmax(scores, axis=0)
    max_scores = scores[cls_ids, np.arange(scores.shape[1])]
    mask = max_scores >= conf_thresh

    boxes_xyxy = []
    confs = []
    chosen_cls = []
    for a in np.where(mask)[0]:
        cx, cy, bw, bh = out[0, a], out[1, a], out[2, a], out[3, a]
        x1 = max(0.0, min(1.0, ((cx - bw * 0.5 - pad_x) / scale) / w))
        y1 = max(0.0, min(1.0, ((cy - bh * 0.5 - pad_y) / scale) / h))
        x2 = max(0.0, min(1.0, ((cx + bw * 0.5 - pad_x) / scale) / w))
        y2 = max(0.0, min(1.0, ((cy + bh * 0.5 - pad_y) / scale) / h))
        boxes_xyxy.append([x1, y1, x2 - x1, y2 - y1])
        confs.append(float(max_scores[a]))
        chosen_cls.append(int(cls_ids[a]))

    detections = []
    if boxes_xyxy:
        # Per-class NMS via cv2.dnn.NMSBoxes
        by_cls: dict[int, list[int]] = {}
        for idx, c in enumerate(chosen_cls):
            by_cls.setdefault(c, []).append(idx)
        for c, idxs in by_cls.items():
            c_boxes = [boxes_xyxy[i] for i in idxs]
            c_confs = [confs[i] for i in idxs]
            keep = cv2.dnn.NMSBoxes(c_boxes, c_confs, conf_thresh, 0.45)
            for k in np.array(keep).flatten().tolist():
                orig_idx = idxs[k]
                x, y, bw, bh = boxes_xyxy[orig_idx]
                detections.append(
                    {
                        "classId": c,
                        "label": labels[c],
                        "confidence": round(float(confs[orig_idx]), 4),
                        "left": round(float(x), 4),
                        "top": round(float(y), 4),
                        "right": round(float(x + bw), 4),
                        "bottom": round(float(y + bh), 4),
                    }
                )
    detections.sort(key=lambda d: d["confidence"], reverse=True)
    return detections, infer_ms


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    sess = ort.InferenceSession(
        str(root / "assets" / "models" / "yolov8n_oiv7_416.onnx"),
        providers=["CPUExecutionProvider"],
    )
    labels = (root / "assets" / "models" / "oiv7_labels.txt").read_text().splitlines()

    scene_path = Path(
        "/home/falcon/.gemini/antigravity-cli/brain/5d310ef7-3a81-4636-acdd-ff45a002c1fb/webcam_developer_desk_1795714909858.jpg"
    )
    img = cv2.imread(str(scene_path))
    detections, infer_ms = letterbox_and_run(sess, labels, img, conf_thresh=0.25)
    print(f"Scene inference: {infer_ms:.1f} ms, detections={len(detections)}")
    for d in detections:
        print(f"  - {d['label']} ({d['confidence']*100:.1f}%) box=({d['left']}, {d['top']}, {d['right']}, {d['bottom']})")

    out_json = Path("/tmp/whatisthat_scene_detections.json")
    out_json.write_text(json.dumps({"inferenceMs": round(infer_ms), "detections": detections}, indent=2))

    # Also test live /dev/video0 webcam capture & ONNX speed in memory (no private frame saved)
    cap = cv2.VideoCapture(0)
    if cap.isOpened():
        ok, frame = cap.read()
        cap.release()
        if ok and frame is not None:
            cam_dets, cam_ms = letterbox_and_run(sess, labels, frame, conf_thresh=0.28)
            print(f"Live /dev/video0 inference: {cam_ms:.1f} ms, frame={frame.shape[1]}x{frame.shape[0]}, detections={len(cam_dets)}")
            for d in cam_dets[:8]:
                print(f"  - [webcam] {d['label']} ({d['confidence']*100:.1f}%)")
        else:
            print("Live /dev/video0 opened but failed to read frame.")
    else:
        print("Live /dev/video0 could not be opened in current session.")


if __name__ == "__main__":
    main()
