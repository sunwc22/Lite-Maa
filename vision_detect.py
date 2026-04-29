import json
import os
import shutil
import sys
from collections import deque
from difflib import SequenceMatcher

import numpy as np
from PIL import Image

try:
    import pytesseract
except ImportError:
    pytesseract = None


OCR_AVAILABLE = False
OCR_ERROR = ""

if pytesseract is not None:
    candidates = [
        shutil.which("tesseract"),
        r"D:\Applications\TesseractOCR\tesseract.exe",
        r"C:\Program Files\Tesseract-OCR\tesseract.exe",
        r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
    ]
    tesseract_cmd = next((item for item in candidates if item and os.path.exists(item)), None)
    if tesseract_cmd:
        pytesseract.pytesseract.tesseract_cmd = tesseract_cmd
        OCR_AVAILABLE = True
    else:
        OCR_ERROR = "tesseract.exe not found"
else:
    OCR_ERROR = "pytesseract is not installed"


def region(img, left, top, right, bottom):
    h, w = img.shape[:2]
    x1 = max(0, min(w, int(w * left)))
    y1 = max(0, min(h, int(h * top)))
    x2 = max(0, min(w, int(w * right)))
    y2 = max(0, min(h, int(h * bottom)))
    return img[y1:y2, x1:x2], x1, y1


def stats_for(mask):
    return float(mask.mean()) if mask.size else 0.0


def normalize_text(text):
    return "".join(ch for ch in text.lower().strip() if ch.isalnum() or "\u4e00" <= ch <= "\u9fff")


def has_cjk(text):
    return any("\u4e00" <= ch <= "\u9fff" for ch in text)


def fuzzy_ratio(text, target):
    text = normalize_text(text)
    target = normalize_text(target)
    if not text or not target:
        return 0.0
    if len(text) < 2:
        return 0.0
    if has_cjk(target) and not has_cjk(text):
        return 0.0
    if not has_cjk(target) and len(text) < 3:
        return 0.0
    if target in text or text in target:
        return 1.0
    return SequenceMatcher(None, text, target).ratio()


def color_ratios(area):
    if area.size == 0:
        return {key: 0.0 for key in ("bright", "white", "dark", "mid", "neutral_mid", "yellow", "red", "cyan", "pink", "orange")}

    gray = area.mean(axis=2)
    r = area[:, :, 0]
    g = area[:, :, 1]
    b = area[:, :, 2]
    neutral = (
        (np.abs(r.astype(int) - g.astype(int)) < 42)
        & (np.abs(g.astype(int) - b.astype(int)) < 42)
    )
    return {
        "bright": stats_for(gray > 185),
        "white": stats_for((r > 185) & (g > 185) & (b > 185)),
        "dark": stats_for((gray > 25) & (gray < 120)),
        "mid": stats_for((gray > 70) & (gray < 175)),
        "neutral_mid": stats_for(neutral & (gray > 55) & (gray < 170)),
        "yellow": stats_for((r > 185) & (g > 140) & (b < 115)),
        "red": stats_for((r > 170) & (g < 115) & (b < 135)),
        "cyan": stats_for((b > 145) & (g > 115) & (r < 125)),
        "pink": stats_for((r > 180) & (b > 120) & (g < 100)),
        "orange": stats_for((r > 210) & (g > 85) & (g < 180) & (b < 80)),
    }


def components(mask):
    h, w = mask.shape
    seen = np.zeros(mask.shape, dtype=bool)
    result = []

    ys, xs = np.nonzero(mask)
    for sy, sx in zip(ys, xs):
        if seen[sy, sx]:
            continue
        q = deque([(sx, sy)])
        seen[sy, sx] = True
        min_x = max_x = sx
        min_y = max_y = sy
        count = 0

        while q:
            x, y = q.popleft()
            count += 1
            min_x = min(min_x, x)
            max_x = max(max_x, x)
            min_y = min(min_y, y)
            max_y = max(max_y, y)

            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < w and 0 <= ny < h and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    q.append((nx, ny))

        result.append((count, min_x, min_y, max_x, max_y))

    result.sort(reverse=True)
    return result


def preprocess_for_ocr(img):
    pil = Image.fromarray(img)
    pil = pil.resize((pil.width * 2, pil.height * 2), Image.Resampling.LANCZOS)
    gray = pil.convert("L")
    arr = np.asarray(gray)
    threshold = max(120, int(arr.mean() + arr.std() * 0.25))
    binary = np.where(arr > threshold, 255, 0).astype(np.uint8)
    return Image.fromarray(binary, mode="L")


def run_ocr_data(image):
    try:
        return pytesseract.image_to_data(image, lang="chi_sim+eng", config="--psm 6", output_type=pytesseract.Output.DICT)
    except Exception:
        return pytesseract.image_to_data(image, lang="eng", config="--psm 6", output_type=pytesseract.Output.DICT)


def run_ocr_string(image):
    try:
        return pytesseract.image_to_string(image, lang="chi_sim+eng", config="--psm 6")
    except Exception:
        return pytesseract.image_to_string(image, lang="eng", config="--psm 6")


def ocr_text_score(img, search_region, targets):
    if not OCR_AVAILABLE:
        return 0.0, ""

    crop, _, _ = region(img, *search_region)
    if crop.size == 0:
        return 0.0, ""

    processed = preprocess_for_ocr(crop)
    text = run_ocr_string(processed)
    score = max((fuzzy_ratio(text, target) for target in targets), default=0.0)
    return score, text.strip()


def ocr_candidates(img, targets, search_region, state):
    if not OCR_AVAILABLE:
        return None

    crop, off_x, off_y = region(img, *search_region)
    if crop.size == 0:
        return None

    processed = preprocess_for_ocr(crop)
    data = run_ocr_data(processed)
    best = None

    for i, raw in enumerate(data.get("text", [])):
        if not raw or not raw.strip():
            continue
        try:
            ocr_conf = float(data["conf"][i]) / 100.0
        except ValueError:
            ocr_conf = 0.0
        if ocr_conf < 0.20:
            continue

        text_score = max(fuzzy_ratio(raw, target) for target in targets)
        if text_score < 0.62:
            continue

        x = off_x + (data["left"][i] + data["width"][i] / 2) / 2
        y = off_y + (data["top"][i] + data["height"][i] / 2) / 2
        candidate = {
            "state": state,
            "x": int(x),
            "y": int(y),
            "confidence": min(0.99, text_score * 0.72 + max(0.0, ocr_conf) * 0.28),
            "text": raw.strip(),
            "method": "ocr",
        }
        if best is None or candidate["confidence"] > best["confidence"]:
            best = candidate

    if best:
        return best

    full_text = run_ocr_string(processed)
    text_score = max(fuzzy_ratio(full_text, target) for target in targets)
    if text_score >= 0.68:
        h, w = img.shape[:2]
        left, top, right, bottom = search_region
        y = int(h * ((top + bottom) / 2))
        if state == "wake":
            y = int(h * 0.71)
        elif state == "start":
            y = int(h * 0.82)
        return {
            "state": state,
            "x": int(w * ((left + right) / 2)),
            "y": y,
            "confidence": min(0.92, text_score),
            "text": full_text.strip(),
            "method": "ocr-line",
        }

    return None


def detect_text_targets(img):
    wake = ocr_candidates(
        img,
        targets=["\u5f00\u59cb\u5524\u9192", "\u958b\u59cb\u559a\u9192", "startwake"],
        search_region=(0.30, 0.48, 0.70, 0.86),
        state="wake",
    )
    if wake:
        return wake

    start = ocr_candidates(
        img,
        targets=["start", "touchscreen", "\u70b9\u51fb\u5f00\u59cb"],
        search_region=(0.28, 0.60, 0.72, 0.96),
        state="start",
    )
    if start:
        return start

    return None


def detect_loading(img):
    gray = img.mean(axis=2)
    if stats_for(gray < 16) > 0.92:
        return 0.95

    if stats_for(gray < 80) < 0.55:
        return 0.0

    bottom, _, _ = region(img, 0.0, 0.93, 1.0, 1.0)
    yellow = (bottom[:, :, 0] > 180) & (bottom[:, :, 1] > 145) & (bottom[:, :, 2] < 85)
    ys, xs = np.nonzero(yellow)
    if len(xs) > 80 and len(ys) > 0 and (xs.max() - xs.min()) > img.shape[1] * 0.45 and (ys.max() - ys.min()) < bottom.shape[0] * 0.35:
        return 0.9
    return 0.0


def detect_home(img):
    top_stats = color_ratios(region(img, 0.48, 0.02, 0.96, 0.16)[0])
    top_left_stats = color_ratios(region(img, 0.00, 0.02, 0.26, 0.14)[0])
    terminal_stats = color_ratios(region(img, 0.54, 0.16, 0.88, 0.44)[0])
    menu_stats = color_ratios(region(img, 0.52, 0.42, 0.96, 0.93)[0])
    left_stats = color_ratios(region(img, 0.00, 0.38, 0.25, 0.62)[0])
    wake_stats = color_ratios(region(img, 0.40, 0.61, 0.60, 0.76)[0])

    anchors = [
        top_stats["white"] > 0.05 and top_stats["dark"] > 0.04,
        (top_stats["cyan"] + top_stats["red"] + top_stats["yellow"]) > 0.015,
        top_left_stats["white"] > 0.10 and top_left_stats["dark"] > 0.03,
        terminal_stats["dark"] > 0.25 and terminal_stats["white"] > 0.025,
        menu_stats["dark"] > 0.24 and menu_stats["neutral_mid"] > 0.13,
        left_stats["white"] > 0.03 and left_stats["dark"] > 0.08,
    ]
    wake_like = wake_stats["neutral_mid"] > 0.20 and wake_stats["white"] > 0.08
    matched = sum(1 for item in anchors if item)
    if wake_like:
        matched -= 1
    return max(0.0, min(1.0, matched / 6))


def detect_announcement(img):
    h, w = img.shape[:2]
    overlay = color_ratios(region(img, 0.00, 0.00, 1.00, 1.00)[0])
    modal = color_ratios(region(img, 0.04, 0.08, 0.96, 0.95)[0])
    tabs = color_ratios(region(img, 0.24, 0.10, 0.80, 0.24)[0])
    left_list = color_ratios(region(img, 0.06, 0.25, 0.27, 0.82)[0])
    content = color_ratios(region(img, 0.27, 0.24, 0.92, 0.90)[0])
    close = color_ratios(region(img, 0.90, 0.06, 0.98, 0.18)[0])
    top_strip = color_ratios(region(img, 0.05, 0.09, 0.95, 0.22)[0])
    bottom_shadow = color_ratios(region(img, 0.04, 0.86, 0.96, 0.96)[0])

    left_rows = [
        color_ratios(region(img, 0.07, 0.26, 0.25, 0.35)[0]),
        color_ratios(region(img, 0.07, 0.37, 0.25, 0.46)[0]),
        color_ratios(region(img, 0.07, 0.48, 0.25, 0.57)[0]),
        color_ratios(region(img, 0.07, 0.59, 0.25, 0.68)[0]),
    ]
    row_hits = sum(1 for row in left_rows if row["dark"] > 0.18 and row["neutral_mid"] > 0.12 and row["white"] > 0.025)

    close_area = region(img, 0.90, 0.06, 0.98, 0.18)[0]
    close_gray = close_area.mean(axis=2)
    close_mask = (close_gray > 95) & (close_gray < 210)
    close_components = components(close_mask)
    close_hits = 0
    for comp in close_components:
        x1, y1, x2, y2, count = comp
        cw = max(1, x2 - x1 + 1)
        ch = max(1, y2 - y1 + 1)
        area_ratio = count / float(close_mask.size)
        aspect = cw / float(ch)
        if 0.45 < aspect < 1.75 and area_ratio > 0.035 and cw > close_area.shape[1] * 0.18 and ch > close_area.shape[0] * 0.18:
            close_hits += 1

    score = 0
    score += 1 if overlay["dark"] > 0.25 and overlay["mid"] > 0.25 else 0
    score += 1 if modal["dark"] > 0.18 and modal["bright"] > 0.10 else 0
    score += 1 if tabs["neutral_mid"] > 0.22 and tabs["white"] > 0.045 and top_strip["dark"] > 0.22 else 0
    score += 1 if left_list["dark"] > 0.20 and left_list["white"] > 0.055 and row_hits >= 2 else 0
    score += 1 if content["bright"] > 0.25 and (content["cyan"] + content["red"] + content["yellow"]) > 0.05 else 0
    score += 1 if close["neutral_mid"] > 0.18 and close["white"] > 0.08 and close_hits > 0 else 0
    score += 1 if bottom_shadow["dark"] > 0.22 and bottom_shadow["mid"] > 0.18 else 0

    required_layout = (
        row_hits >= 2
        and close_hits > 0
        and tabs["neutral_mid"] > 0.22
        and tabs["white"] > 0.045
        and content["bright"] > 0.22
    )

    if required_layout and score >= 6:
        return {
            "state": "announcement",
            "x": int(w * 0.94),
            "y": int(h * 0.105),
            "confidence": score / 7,
            "method": "visual",
        }
    return None


def detect_duel_channel(img):
    h, w = img.shape[:2]
    modal = color_ratios(region(img, 0.26, 0.08, 0.99, 0.96)[0])
    hero = color_ratios(region(img, 0.28, 0.16, 0.78, 0.63)[0])
    right_panel = color_ratios(region(img, 0.76, 0.16, 0.98, 0.63)[0])
    bottom_buttons = color_ratios(region(img, 0.28, 0.72, 0.98, 0.96)[0])

    score = 0
    score += 1 if modal["white"] > 0.14 and modal["dark"] > 0.05 else 0
    score += 1 if hero["yellow"] > 0.12 and hero["pink"] > 0.08 else 0
    score += 1 if right_panel["dark"] > 0.30 and right_panel["orange"] > 0.01 else 0
    score += 1 if bottom_buttons["yellow"] > 0.10 and bottom_buttons["orange"] > 0.03 else 0

    if score >= 3:
        text_score, text = ocr_text_score(
            img,
            (0.26, 0.08, 0.99, 0.96),
            ["Duel Channel", "\u52a0\u5165\u8d5b\u4e8b", "\u9891\u9053\u516c\u544a", "\u7eff\u85e4\u57ce"],
        )
        if OCR_AVAILABLE and text_score < 0.42:
            return None
        return {
            "state": "duel_channel",
            "x": int(w * 0.84),
            "y": int(h * 0.89),
            "confidence": min(0.99, score / 4 * 0.65 + max(text_score, 0.35) * 0.35),
            "method": "visual-text" if text_score >= 0.42 else "visual",
            "text": text,
        }
    return None


def detect_duel_event_select(img):
    h, w = img.shape[:2]
    top = color_ratios(region(img, 0.00, 0.00, 1.00, 0.58)[0])
    header = color_ratios(region(img, 0.02, 0.15, 0.62, 0.44)[0])
    cards = color_ratios(region(img, 0.02, 0.62, 0.88, 0.93)[0])
    right_button = color_ratios(region(img, 0.88, 0.58, 0.99, 0.96)[0])

    score = 0
    score += 1 if top["dark"] > 0.25 and top["mid"] > 0.20 else 0
    score += 1 if header["yellow"] > 0.12 and header["dark"] > 0.08 else 0
    score += 1 if cards["dark"] > 0.18 and cards["red"] > 0.01 else 0
    score += 1 if right_button["neutral_mid"] > 0.35 and right_button["dark"] > 0.05 else 0

    if score >= 3:
        text_score, text = ocr_text_score(
            img,
            (0.00, 0.08, 1.00, 0.96),
            ["\u9009\u62e9\u8d5b\u4e8b", "\u8bf7\u9009\u62e9\u4e00\u79cd\u6a21\u5f0f\u8fdb\u884c\u5bf9\u51b3", "\u81ea\u5a31\u81ea\u4e50", "\u7ade\u731c\u5bf9\u51b3"],
        )
        if OCR_AVAILABLE and text_score < 0.42:
            return None
        return {
            "state": "duel_event_select",
            "x": int(w * 0.72),
            "y": int(h * 0.79),
            "confidence": min(0.99, score / 4 * 0.65 + max(text_score, 0.35) * 0.35),
            "method": "visual-text" if text_score >= 0.42 else "visual",
            "text": text,
        }
    return None


def detect_duel_casual_selected(img):
    h, w = img.shape[:2]
    top = color_ratios(region(img, 0.00, 0.00, 1.00, 0.58)[0])
    title = color_ratios(region(img, 0.02, 0.08, 0.42, 0.30)[0])
    selected_card = color_ratios(region(img, 0.58, 0.62, 0.86, 0.94)[0])
    start_button = color_ratios(region(img, 0.87, 0.62, 0.99, 0.94)[0])

    score = 0
    score += 1 if top["dark"] > 0.28 and top["yellow"] > 0.03 else 0
    score += 1 if title["yellow"] > 0.08 and title["dark"] > 0.16 else 0
    score += 1 if selected_card["yellow"] > 0.20 and selected_card["dark"] > 0.12 else 0
    score += 1 if start_button["yellow"] > 0.35 and start_button["dark"] > 0.05 else 0

    if score >= 3:
        text_score, text = ocr_text_score(
            img,
            (0.00, 0.08, 1.00, 0.96),
            ["\u5f00\u59cb\u6e38\u620f", "\u81ea\u5a31\u81ea\u4e50", "\u5355\u4eba\u81ea\u5a31\u81ea\u4e50", "GOOD GUESS GAMING"],
        )
        if OCR_AVAILABLE and text_score < 0.42:
            return None
        return {
            "state": "duel_casual_selected",
            "x": int(w * 0.925),
            "y": int(h * 0.80),
            "confidence": min(0.99, score / 4 * 0.65 + max(text_score, 0.35) * 0.35),
            "method": "visual-text" if text_score >= 0.42 else "visual",
            "text": text,
        }
    return None


def detect_duel_result(img):
    h, w = img.shape[:2]
    title = color_ratios(region(img, 0.00, 0.02, 0.28, 0.18)[0])
    ranking = color_ratios(region(img, 0.66, 0.02, 0.99, 0.78)[0])
    bottom_bar = color_ratios(region(img, 0.00, 0.78, 1.00, 1.00)[0])
    home_button = color_ratios(region(img, 0.76, 0.82, 0.99, 0.99)[0])
    top_left_button = color_ratios(region(img, 0.02, 0.02, 0.14, 0.12)[0])
    event_header = color_ratios(region(img, 0.02, 0.15, 0.62, 0.44)[0])
    game_board = color_ratios(region(img, 0.16, 0.12, 0.84, 0.78)[0])
    game_support = color_ratios(region(img, 0.00, 0.78, 1.00, 1.00)[0])

    looks_like_result_header = title["white"] > 0.18 and title["dark"] > 0.10
    looks_like_result_home = home_button["yellow"] > 0.34 and home_button["dark"] > 0.08
    looks_like_event_select = event_header["yellow"] > 0.10 and top_left_button["white"] > 0.12
    looks_like_game = (
        game_board["mid"] > 0.34
        and game_board["bright"] > 0.05
        and game_support["dark"] > 0.10
        and not (looks_like_result_header and looks_like_result_home)
    )
    if looks_like_event_select or looks_like_game:
        return None

    score = 0
    score += 1 if title["white"] > 0.18 and title["dark"] > 0.10 else 0
    score += 1 if ranking["dark"] > 0.34 and ranking["white"] > 0.04 and ranking["yellow"] < 0.05 else 0
    score += 1 if bottom_bar["dark"] > 0.22 and bottom_bar["yellow"] > 0.06 else 0
    score += 1 if home_button["yellow"] > 0.34 and home_button["dark"] > 0.08 else 0

    if score >= 4:
        text_score, text = ocr_text_score(
            img,
            (0.00, 0.00, 1.00, 1.00),
            ["\u8fd4\u56de\u4e3b\u9875", "\u6bd4\u8d5b\u7ed3\u675f", "\u6700\u7ec8\u793c\u7269\u70b9\u6570", "\u81ea\u5a31\u81ea\u4e50"],
        )
        if OCR_AVAILABLE and text_score < 0.45:
            return None
        return {
            "state": "duel_result",
            "x": int(w * 0.875),
            "y": int(h * 0.92),
            "confidence": min(0.99, score / 4 * 0.65 + max(text_score, 0.40) * 0.35),
            "method": "visual-text" if text_score >= 0.45 else "visual",
            "text": text,
        }
    return None


def detect_duel_game(img):
    h, w = img.shape[:2]
    board = color_ratios(region(img, 0.16, 0.12, 0.84, 0.78)[0])
    left_hud = color_ratios(region(img, 0.00, 0.03, 0.22, 0.45)[0])
    right_hud = color_ratios(region(img, 0.76, 0.03, 1.00, 0.45)[0])
    support_buttons = color_ratios(region(img, 0.00, 0.78, 1.00, 1.00)[0])
    center_timer = color_ratios(region(img, 0.36, 0.36, 0.64, 0.66)[0])

    score = 0
    score += 1 if board["mid"] > 0.35 and board["bright"] > 0.05 else 0
    score += 1 if left_hud["red"] > 0.02 and left_hud["dark"] > 0.25 else 0
    score += 1 if right_hud["cyan"] > 0.03 and right_hud["dark"] > 0.18 else 0
    score += 1 if support_buttons["yellow"] > 0.08 and support_buttons["dark"] > 0.12 else 0
    score += 1 if center_timer["white"] > 0.08 and center_timer["dark"] > 0.10 else 0

    if score >= 4:
        text_score, text = ocr_text_score(
            img,
            (0.00, 0.34, 1.00, 1.00),
            ["ROUND", "\u8bf7\u9009\u62e9\u652f\u6301\u7684\u961f\u4f0d", "\u672c\u8f6e\u89c2\u671b", "\u652f\u6301"],
        )
        if OCR_AVAILABLE and text_score < 0.38:
            return None
        return {
            "state": "duel_game",
            "x": int(w * 0.50),
            "y": int(h * 0.50),
            "confidence": min(0.99, score / 5 * 0.65 + max(text_score, 0.32) * 0.35),
            "method": "visual-text" if text_score >= 0.38 else "visual",
            "text": text,
        }
    return None


def detect_start(img):
    h, w = img.shape[:2]
    roi, off_x, off_y = region(img, 0.35, 0.70, 0.65, 0.96)
    yellow = (
        (roi[:, :, 0] > 165)
        & (roi[:, :, 1] > 125)
        & (roi[:, :, 2] < 105)
        & (np.abs(roi[:, :, 0].astype(int) - roi[:, :, 1].astype(int)) < 100)
    )

    for count, x1, y1, x2, y2 in components(yellow)[:8]:
        bw = x2 - x1 + 1
        bh = y2 - y1 + 1
        if count > 35 and w * 0.025 < bw < w * 0.16 and h * 0.035 < bh < h * 0.16:
            return {
                "state": "start",
                "x": int(off_x + (x1 + x2) / 2),
                "y": int(off_y + (y1 + y2) / 2),
                "confidence": min(0.99, count / 400.0),
                "method": "visual",
            }
    return None


def detect_wake(img):
    h, w = img.shape[:2]
    roi, off_x, off_y = region(img, 0.34, 0.55, 0.66, 0.84)
    gray = roi.mean(axis=2)
    neutral = (
        (gray > 45)
        & (gray < 165)
        & (np.abs(roi[:, :, 0].astype(int) - roi[:, :, 1].astype(int)) < 42)
        & (np.abs(roi[:, :, 1].astype(int) - roi[:, :, 2].astype(int)) < 42)
    )
    white = (roi[:, :, 0] > 175) & (roi[:, :, 1] > 175) & (roi[:, :, 2] > 175)

    candidates = []
    for count, x1, y1, x2, y2 in components(neutral):
        bw = x2 - x1 + 1
        bh = y2 - y1 + 1
        center_x = off_x + (x1 + x2) / 2
        center_y = off_y + (y1 + y2) / 2
        if not (w * 0.12 < bw < w * 0.34 and h * 0.045 < bh < h * 0.16):
            continue
        if not (w * 0.38 < center_x < w * 0.62 and h * 0.56 < center_y < h * 0.82):
            continue
        button_white = white[max(0, y1):min(white.shape[0], y2 + 1), max(0, x1):min(white.shape[1], x2 + 1)]
        white_ratio = stats_for(button_white)
        if white_ratio > 0.015:
            confidence = min(0.99, 0.45 + count / max(1.0, bw * bh) * 0.35 + white_ratio * 2.0)
            candidates.append((confidence, center_x, center_y))

    if candidates:
        confidence, center_x, center_y = max(candidates)
        return {
            "state": "wake",
            "x": int(w * 0.50),
            "y": int(h * 0.70),
            "confidence": confidence,
            "method": "visual",
        }
    return None


def emit(result):
    result["ocr"] = OCR_AVAILABLE
    if not OCR_AVAILABLE:
        result["ocr_error"] = OCR_ERROR
    print(json.dumps(result, ensure_ascii=True))


def main():
    if len(sys.argv) != 2:
        emit({"state": "error", "message": "usage: vision_detect.py image", "confidence": 0.0})
        return 2

    img = np.asarray(Image.open(sys.argv[1]).convert("RGB"))

    duel_result = detect_duel_result(img)
    if duel_result:
        emit(duel_result)
        return 0

    duel_game = detect_duel_game(img)
    if duel_game:
        emit(duel_game)
        return 0

    casual_selected = detect_duel_casual_selected(img)
    if casual_selected:
        emit(casual_selected)
        return 0

    event_select = detect_duel_event_select(img)
    if event_select:
        emit(event_select)
        return 0

    duel_channel = detect_duel_channel(img)
    if duel_channel:
        emit(duel_channel)
        return 0

    announcement = detect_announcement(img)
    if announcement:
        emit(announcement)
        return 0

    loading_conf = detect_loading(img)
    if loading_conf > 0:
        emit({"state": "loading", "confidence": loading_conf})
        return 0

    home_conf = detect_home(img)
    if home_conf >= 0.78:
        emit({"state": "home", "confidence": home_conf, "method": "visual"})
        return 0

    text_target = detect_text_targets(img)
    if text_target:
        emit(text_target)
        return 0

    start = detect_start(img)
    if start:
        emit(start)
        return 0

    wake = detect_wake(img)
    if wake:
        emit(wake)
        return 0

    emit({"state": "unknown", "confidence": 0.0})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
