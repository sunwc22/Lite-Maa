import json
import os
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from PIL import Image

try:
    import pytesseract
except ImportError:
    pytesseract = None

try:
    from paddleocr import PaddleOCR
except ImportError:
    PaddleOCR = None

OCR_ENGINE = ""
PADDLE_OCR = None


def configure_tesseract():
    if pytesseract is None:
        return False, "pytesseract is not installed"

    candidates = [
        shutil.which("tesseract"),
        r"D:\Applications\TesseractOCR\tesseract.exe",
        r"C:\Program Files\Tesseract-OCR\tesseract.exe",
        r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
    ]
    tesseract_cmd = next((item for item in candidates if item and os.path.exists(item)), None)
    if not tesseract_cmd:
        return False, "tesseract.exe not found"

    pytesseract.pytesseract.tesseract_cmd = tesseract_cmd
    return True, ""


def configure_ocr():
    global OCR_ENGINE, PADDLE_OCR

    if PaddleOCR is not None:
        try:
            init_options = [
                {
                    "lang": "ch",
                    "ocr_version": "PP-OCRv5",
                    "text_detection_model_name": "PP-OCRv5_mobile_det",
                    "text_recognition_model_name": "PP-OCRv5_mobile_rec",
                    "use_doc_orientation_classify": False,
                    "use_doc_unwarping": False,
                    "use_textline_orientation": False,
                },
                {
                    "lang": "ch",
                    "use_doc_orientation_classify": False,
                    "use_doc_unwarping": False,
                    "use_textline_orientation": False,
                },
                {"lang": "ch"},
            ]
            last_error = None
            for options in init_options:
                try:
                    PADDLE_OCR = PaddleOCR(**options)
                    last_error = None
                    break
                except Exception as exc:
                    last_error = exc
            if PADDLE_OCR is None:
                raise last_error
            OCR_ENGINE = "paddleocr"
            return True, "", OCR_ENGINE
        except Exception as exc:
            paddle_error = f"paddleocr unavailable: {exc}"
    else:
        paddle_error = "paddleocr is not installed"

    ok, error = configure_tesseract()
    OCR_ENGINE = "tesseract" if ok else ""
    if ok:
        return True, paddle_error, OCR_ENGINE
    return False, f"{paddle_error}; {error}", OCR_ENGINE


def crop(img, box):
    w, h = img.size
    left, top, right, bottom = box
    return img.crop((int(w * left), int(h * top), int(w * right), int(h * bottom)))


def preprocess_for_ocr(img, invert=False):
    scale = 2
    gray = img.resize((img.width * scale, img.height * scale), Image.Resampling.LANCZOS).convert("L")
    arr = np.asarray(gray)
    if invert:
        arr = 255 - arr
    threshold = max(110, int(arr.mean() + arr.std() * 0.10))
    binary = np.where(arr > threshold, 255, 0).astype(np.uint8)
    return Image.fromarray(binary, mode="L")


def clean_text(text):
    lines = []
    for line in text.replace("\r", "\n").split("\n"):
        line = " ".join(line.split())
        if line:
            lines.append(line)
    return "\n".join(lines)


def flatten_paddle_result(result):
    lines = []

    def walk(item):
        if hasattr(item, "json") and isinstance(item.json, dict):
            walk(item.json)
            return
        if isinstance(item, dict):
            if "rec_texts" in item and isinstance(item["rec_texts"], list):
                for text in item["rec_texts"]:
                    walk(text)
                return
            if "res" in item:
                walk(item["res"])
                return
            for value in item.values():
                walk(value)
            return
        if isinstance(item, str):
            if item.strip():
                lines.append(item.strip())
            return
        if isinstance(item, tuple) and item and isinstance(item[0], str):
            if item[0].strip():
                lines.append(item[0].strip())
            return
        if isinstance(item, list):
            if len(item) >= 2 and isinstance(item[1], tuple) and item[1] and isinstance(item[1][0], str):
                text = item[1][0].strip()
                if text:
                    lines.append(text)
                return
            for child in item:
                walk(child)

    walk(result)
    return clean_text("\n".join(lines))


def paddle_text_items(result):
    items = []

    def normalize_box(box):
        if box is None:
            return None
        if hasattr(box, "tolist"):
            box = box.tolist()
        if not isinstance(box, (list, tuple)) or not box:
            return None
        if all(isinstance(value, (int, float)) for value in box) and len(box) >= 4:
            left, top, right, bottom = [float(value) for value in box[:4]]
            return [[left, top], [right, top], [right, bottom], [left, bottom]]
        points = []
        for point in box:
            if hasattr(point, "tolist"):
                point = point.tolist()
            if isinstance(point, (list, tuple)) and len(point) >= 2:
                points.append([float(point[0]), float(point[1])])
        return points if points else None

    def add_item(text, box=None, score=None):
        text = str(text).strip()
        if not text:
            return
        norm_box = normalize_box(box)
        if norm_box:
            xs = [point[0] for point in norm_box]
            ys = [point[1] for point in norm_box]
            center_x = sum(xs) / len(xs)
            center_y = sum(ys) / len(ys)
        else:
            center_x = None
            center_y = None
        items.append({
            "text": text,
            "box": norm_box,
            "score": score,
            "center_x": center_x,
            "center_y": center_y,
        })

    def walk(item):
        if hasattr(item, "json") and isinstance(item.json, dict):
            walk(item.json)
            return
        if isinstance(item, dict):
            if "res" in item:
                walk(item["res"])
                return
            texts = item.get("rec_texts")
            if isinstance(texts, list):
                boxes = item.get("rec_polys") or item.get("dt_polys") or item.get("rec_boxes") or item.get("dt_boxes") or []
                scores = item.get("rec_scores") or item.get("scores") or []
                for index, text in enumerate(texts):
                    box = boxes[index] if index < len(boxes) else None
                    score = scores[index] if index < len(scores) else None
                    add_item(text, box, score)
                return
            for value in item.values():
                walk(value)
            return
        if isinstance(item, list):
            if len(item) >= 2 and isinstance(item[1], tuple) and item[1] and isinstance(item[1][0], str):
                score = item[1][1] if len(item[1]) > 1 else None
                add_item(item[1][0], item[0], score)
                return
            for child in item:
                walk(child)

    walk(result)
    return items


def ocr_region(img, box, invert=False, psm=6):
    if OCR_ENGINE == "paddleocr" and PADDLE_OCR is not None:
        area = crop(img, box).convert("RGB")
        arr = np.asarray(area)
        if invert:
            arr = 255 - arr
        try:
            result = PADDLE_OCR.predict(arr)
        except AttributeError:
            try:
                result = PADDLE_OCR.ocr(arr)
            except Exception:
                return ""
        except Exception:
            return ""
        return flatten_paddle_result(result)

    if pytesseract is None:
        return ""
    processed = preprocess_for_ocr(crop(img, box), invert=invert)
    try:
        text = pytesseract.image_to_string(processed, lang="chi_sim+eng", config=f"--psm {psm}")
    except Exception:
        text = pytesseract.image_to_string(processed, lang="eng", config=f"--psm {psm}")
    return clean_text(text)


def ocr_count_region(img, box):
    if OCR_ENGINE == "paddleocr" and PADDLE_OCR is not None:
        area = crop(img, box).convert("RGB")
        lines = []
        seen = set()
        for scale in (4, 6):
            enlarged = area.resize((area.width * scale, area.height * scale), Image.Resampling.LANCZOS)
            for candidate in (enlarged, Image.fromarray(255 - np.asarray(enlarged), mode="RGB")):
                try:
                    result = PADDLE_OCR.predict(np.asarray(candidate))
                except Exception:
                    continue
                text = flatten_paddle_result(result)
                for line in text.splitlines():
                    if line and line not in seen:
                        lines.append(line)
                        seen.add(line)
        return "\n".join(lines)

    if pytesseract is None:
        return ""

    variants = [
        ocr_region(img, box, invert=False, psm=11),
        ocr_region(img, box, invert=True, psm=11),
        ocr_region(img, box, invert=False, psm=7),
        ocr_region(img, box, invert=True, psm=7),
    ]
    lines = []
    seen = set()
    for text in variants:
        for line in text.splitlines():
            if line and line not in seen:
                lines.append(line)
                seen.add(line)
    return "\n".join(lines)


def parse_multiplier_counts(text, allow_bare_numbers=True):
    counts = []
    for item in re.findall(r"[xX×*]\s*(\d+)", text or ""):
        value = int(item)
        if value > 0 and value not in counts:
            counts.append(value)
    if not allow_bare_numbers:
        return counts
    for item in re.findall(r"\b(\d{1,2})\b", text or ""):
        value = int(item)
        if 0 < value < 100 and value not in counts:
            counts.append(value)
    return counts


def parse_slot_count(text):
    source = text or ""
    marked = re.findall(r"[xX×脳*≠]\s*(\d{1,2})", source)
    if marked:
        values = [int(item) for item in marked if int(item) > 0]
        return values[0] if values else None

    values = []
    for item in re.findall(r"\b(\d{1,2})\b", source):
        value = int(item)
        if value > 0 and value not in values:
            values.append(value)
    return values[0] if len(values) == 1 else None




def parse_remaining_gifts(text):
    values = []
    for item in re.findall(r"\d{4,}", text or ""):
        value = int(item)
        if value > 0:
            values.append(value)
    return max(values) if values else None


def parse_final_gifts(text):
    values = []
    for item in re.findall(r"\d+", text or ""):
        value = int(item)
        if 0 <= value <= 999999:
            values.append(value)
    return max(values) if values else None

def parse_enemy_names(text):
    names = []
    for line in (text or "").splitlines():
        line = line.strip()
        if not line:
            continue
        match = re.match(r"^([^:\uff1a]{2,16})[:\uff1a]", line)
        if not match:
            continue
        name = re.sub(r"\s+", "", match.group(1))
        if not re.search(r"[\u4e00-\u9fff]", name):
            continue
        if name and name not in names:
            names.append(name)
    return names

def extract_enemy_count_slots(img, side):
    if side == "left":
        boxes = [
            (0.320, 0.895, 0.385, 0.975),
            (0.380, 0.895, 0.445, 0.975),
            (0.440, 0.895, 0.505, 0.975),
        ]
    else:
        boxes = [
            (0.565, 0.895, 0.635, 0.975),
            (0.615, 0.895, 0.685, 0.975),
            (0.665, 0.895, 0.735, 0.975),
        ]

    result = []
    for index, box in enumerate(boxes):
        text = ocr_count_region(img, box)
        count = parse_slot_count(text)
        result.append({
            "slot": index,
            "count": count,
            "count_text": text,
        })
    return result


def build_enemy_entries(names, counts, detail_text):
    valid_counts = [item for item in counts if item.get("count") is not None]
    entries = []
    for index, name in enumerate(names):
        count_item = valid_counts[index] if index < len(valid_counts) else {}
        count = count_item.get("count") if count_item else None
        count_text = count_item.get("count_text", "") if count_item else ""
        entries.append({
            "slot": index,
            "name": name,
            "count": count,
            "count_text": count_text,
            "detail_text": detail_text,
        })
    return entries


def emit_json(payload):
    # Keep the dataset itself as UTF-8 Chinese text, but make stdout ASCII-safe
    # because Windows PowerShell may run Python with a GBK console encoding.
    print(json.dumps(payload, ensure_ascii=True))


def extract(image_path):
    ok, error, engine = configure_ocr()
    img = Image.open(image_path).convert("RGB")
    now = datetime.now(timezone.utc).isoformat()
    round_text = ocr_region(img, (0.44, 0.80, 0.56, 0.98), invert=False) if ok else ""
    score_text = ocr_region(img, (0.40, 0.02, 0.66, 0.15), invert=False) if ok else ""
    remaining_gifts = parse_remaining_gifts(score_text)
    # Only OCR the bottom detail overlay. The left/right screen edges contain
    # contestant/player names, not enemy descriptions, so avoid those regions.
    bottom_left_detail = ocr_region(img, (0.18, 0.44, 0.48, 0.78), invert=False) if ok else ""
    bottom_right_detail = ocr_region(img, (0.52, 0.44, 0.82, 0.78), invert=False) if ok else ""
    raw_bottom_text = ocr_region(img, (0.18, 0.44, 0.82, 0.78), invert=False) if ok else ""
    left_detail_text = bottom_left_detail
    right_detail_text = bottom_right_detail
    left_enemy_count_text = ocr_count_region(img, (0.335, 0.895, 0.505, 0.975)) if ok else ""
    right_enemy_count_text = ocr_count_region(img, (0.565, 0.895, 0.735, 0.975)) if ok else ""

    left_enemy_names = parse_enemy_names(left_detail_text + "\n" + bottom_left_detail)
    right_enemy_names = parse_enemy_names(right_detail_text + "\n" + bottom_right_detail)
    left_enemy_slots = extract_enemy_count_slots(img, "left") if ok else []
    right_enemy_slots = extract_enemy_count_slots(img, "right") if ok else []
    left_enemies = build_enemy_entries(left_enemy_names, left_enemy_slots, left_detail_text)
    right_enemies = build_enemy_entries(right_enemy_names, right_enemy_slots, right_detail_text)
    left_enemy_counts = [item["count"] for item in left_enemies if item.get("count") is not None]
    right_enemy_counts = [item["count"] for item in right_enemies if item.get("count") is not None]

    record = {
        "timestamp_utc": now,
        "mode": "duel_casual",
        "source_image": str(Path(image_path).resolve()),
        "ocr_available": ok,
        "ocr_error": error,
        "ocr_engine": engine,
        "round": round_text,
        "score": score_text,
        "remaining_gifts": remaining_gifts,
        "bottom_left_detail": bottom_left_detail,
        "bottom_right_detail": bottom_right_detail,
        "raw_bottom_text": raw_bottom_text,
        "left_detail_text": left_detail_text,
        "right_detail_text": right_detail_text,
        "left_enemy_count_text": left_enemy_count_text,
        "right_enemy_count_text": right_enemy_count_text,
        "left_enemy_counts": left_enemy_counts,
        "right_enemy_counts": right_enemy_counts,
        "left_enemy_total": sum(left_enemy_counts) if left_enemy_counts else None,
        "right_enemy_total": sum(right_enemy_counts) if right_enemy_counts else None,
        "left_enemies": left_enemies,
        "right_enemies": right_enemies,
    }
    return record


def extract_gift_value(image_path):
    ok, error, engine = configure_ocr()
    img = Image.open(image_path).convert("RGB")
    score_text = ocr_region(img, (0.40, 0.02, 0.66, 0.15), invert=False) if ok else ""
    return {
        "ok": ok,
        "ocr_error": error,
        "ocr_engine": engine,
        "score": score_text,
        "remaining_gifts": parse_remaining_gifts(score_text),
    }


def extract_final_gift_value(image_path):
    ok, error, engine = configure_ocr()
    img = Image.open(image_path).convert("RGB")
    final_text = ocr_region(img, (0.12, 0.60, 0.34, 0.78), invert=False) if ok else ""
    return {
        "ok": ok,
        "ocr_error": error,
        "ocr_engine": engine,
        "score": final_text,
        "remaining_gifts": parse_final_gifts(final_text),
    }


def locate_support_button(image_path, side):
    ok, error, engine = configure_ocr()
    if not ok or PADDLE_OCR is None:
        return {"ok": False, "ocr_error": error or "paddleocr unavailable", "ocr_engine": engine}

    img = Image.open(image_path).convert("RGB")
    arr = np.asarray(img)
    try:
        result = PADDLE_OCR.predict(arr)
    except AttributeError:
        result = PADDLE_OCR.ocr(arr)

    w, h = img.size
    candidates = []
    for item in paddle_text_items(result):
        text = re.sub(r"\s+", "", item.get("text", ""))
        x = item.get("center_x")
        y = item.get("center_y")
        if x is None or y is None:
            continue
        rx = x / w
        ry = y / h
        if not (0.76 <= ry <= 0.96):
            continue
        if side == "left" and not (0.02 <= rx <= 0.28):
            continue
        if side == "right" and not (0.72 <= rx <= 0.98):
            continue
        if "支持" not in text:
            continue

        priority = 0
        if "全力支持" in text:
            priority += 3
        if text == "支持":
            priority += 2
        if "此队伍" in text:
            priority -= 3
        candidates.append({
            "text": item.get("text", ""),
            "x": int(round(x)),
            "y": int(round(y)),
            "score": item.get("score"),
            "priority": priority,
        })

    candidates.sort(key=lambda item: (item["priority"], item["y"]), reverse=True)
    if not candidates:
        return {
            "ok": True,
            "found": False,
            "ocr_error": error,
            "ocr_engine": engine,
            "candidates": [],
        }

    best = candidates[0]
    return {
        "ok": True,
        "found": True,
        "ocr_error": error,
        "ocr_engine": engine,
        "side": side,
        "x": best["x"],
        "y": best["y"],
        "text": best["text"],
        "candidates": candidates[:5],
    }


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "--support-button":
        side = sys.argv[2].lower()
        if side not in ("left", "right"):
            emit_json({"ok": False, "error": "side must be left or right"})
            return 2
        emit_json(locate_support_button(sys.argv[3], side))
        return 0

    if len(sys.argv) == 3 and sys.argv[1] == "--gift":
        emit_json(extract_gift_value(sys.argv[2]))
        return 0

    if len(sys.argv) == 3 and sys.argv[1] == "--final-gift":
        emit_json(extract_final_gift_value(sys.argv[2]))
        return 0

    if len(sys.argv) == 3 and sys.argv[1] == "--extract":
        record = extract(sys.argv[2])
        has_named_enemy = bool(record.get("left_enemies") or record.get("right_enemies"))
        if not has_named_enemy:
            emit_json({"ok": True, "skipped": True, "reason": "no named enemy detail", "fields": [], "record": record})
            return 0
        non_empty_fields = [
            key for key in (
                "bottom_left_detail",
                "bottom_right_detail",
                "raw_bottom_text",
                "left_enemy_counts",
                "right_enemy_counts",
                "left_enemies",
                "right_enemies",
            ) if record.get(key)
        ]
        emit_json({"ok": True, "fields": non_empty_fields, "record": record})
        return 0

    if len(sys.argv) != 3:
        emit_json({"ok": False, "error": "usage: duel_dataset.py image dataset_jsonl | duel_dataset.py --gift image | duel_dataset.py --final-gift image | duel_dataset.py --extract image | duel_dataset.py --support-button left|right image"})
        return 2

    image_path = sys.argv[1]
    dataset_path = Path(sys.argv[2])
    dataset_path.parent.mkdir(parents=True, exist_ok=True)

    record = extract(image_path)
    has_named_enemy = bool(record.get("left_enemies") or record.get("right_enemies"))
    if not has_named_enemy:
        emit_json({"ok": True, "skipped": True, "reason": "no named enemy detail", "path": str(dataset_path), "fields": [], "record": record})
        return 0

    with dataset_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")

    non_empty_fields = [
        key for key in (
            "bottom_left_detail",
            "bottom_right_detail",
            "raw_bottom_text",
            "left_enemy_counts",
            "right_enemy_counts",
            "left_enemies",
            "right_enemies",
        ) if record.get(key)
    ]
    emit_json({"ok": True, "path": str(dataset_path), "fields": non_empty_fields, "record": record})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
