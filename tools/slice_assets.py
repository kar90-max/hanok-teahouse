#!/usr/bin/env python3
"""
한옥 떡집·다방 — 소스 아트 → Godot 스프라이트 슬라이싱 도구

downloads/ 안의 생성 원본 PNG들을 배경 제거(가장자리 플러드필 + 그림자 인식) 후
개별 투명 PNG로 잘라 assets/ 아래에 저장합니다.

사용법:
    python3 tools/slice_assets.py           # 전체 재생성
    python3 tools/slice_assets.py --debug   # 세그멘테이션 박스 확인용 이미지도 출력

필요 패키지: pillow, numpy, scipy
"""

from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "..", "downloads")
OUT = ROOT
DEBUG = "--debug" in sys.argv

CACHE = {}


# ---------------------------------------------------------------- background
def border_bg(arr: np.ndarray) -> np.ndarray:
    b = np.concatenate([
        arr[0:3].reshape(-1, 3), arr[-3:].reshape(-1, 3),
        arr[:, 0:3].reshape(-1, 3), arr[:, -3:].reshape(-1, 3),
    ])
    return np.median(b, axis=0)


def foreground_mask(arr: np.ndarray, near: int = 12, hard: int = 62,
                    sat_max: float = 0.16, dark_min: float = 3.0) -> np.ndarray:
    """크림색 배경을 지우되, 안쪽의 흰 쌀/오리/말풍선 속은 남긴다.

    1) 테두리에서 시작하는 '거의 배경색' 연결 성분만 배경으로 본다.
    2) 그 배경에 붙어 있는 저채도·약간 어두운 픽셀(그림자)을 같은 배경으로 흡수한다.
    => 전역 색 임계값과 달리 캐릭터 안쪽의 밝은 영역은 절대 지워지지 않는다.
    """
    bg = border_bg(arr)
    diff = np.abs(arr - bg).max(axis=2)
    mx = arr.max(axis=2).astype(np.float32)
    mn = arr.min(axis=2).astype(np.float32)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1.0), 0.0)
    lum = arr.mean(axis=2)
    lum_bg = float(bg.mean())

    definite = diff < near
    lab, _ = ndimage.label(definite)
    border_labels = set(lab[0].tolist()) | set(lab[-1].tolist()) | \
        set(lab[:, 0].tolist()) | set(lab[:, -1].tolist())
    border_labels.discard(0)
    background = np.isin(lab, list(border_labels))

    shadow = (diff < hard) & (sat < sat_max) & (lum < lum_bg - dark_min)
    region = background
    for _ in range(600):
        grown = region | (shadow & ndimage.binary_dilation(region, iterations=1))
        if grown.sum() == region.sum():
            break
        region = grown
    return ~region


def cutout(name: str, near: int = 12, hard: int = 62) -> tuple[np.ndarray, np.ndarray]:
    """원본을 읽어 (RGBA float 배열, 포그라운드 마스크)를 돌려준다."""
    if name in CACHE:
        return CACHE[name]
    im = Image.open(os.path.join(SRC, name + ".png")).convert("RGB")
    arr = np.array(im).astype(np.int16)
    mask = foreground_mask(arr, near=near, hard=hard)

    # 알파 부드럽게 + 가장자리 색 오염(크림색 테두리) 제거
    alpha = ndimage.gaussian_filter(mask.astype(np.float32), 0.7)
    core = ndimage.binary_erosion(mask, iterations=1)
    if core.any():
        _, idx = ndimage.distance_transform_edt(~core, return_indices=True)
        clean = np.array(im)[idx[0], idx[1]]
        edge = mask & (alpha < 0.99)
        clean[~edge] = np.array(im)[~edge]
    else:
        clean = np.array(im)
    rgba = np.dstack([clean.astype(np.uint8), np.clip(alpha * 255.0, 0, 255).astype(np.uint8)])
    CACHE[name] = (rgba, mask)
    return CACHE[name]


# ---------------------------------------------------------------- segmentation
def components(mask: np.ndarray, min_area: int = 400):
    lab, _ = ndimage.label(mask, structure=np.ones((3, 3)))
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        if sl is None:
            continue
        area = int((lab[sl] == i).sum())
        if area < min_area:
            continue
        out.append([sl[1].start, sl[0].start, sl[1].stop, sl[0].stop, area])
    return out


def merge_boxes(boxes, dist: int):
    boxes = [b[:] for b in boxes]
    changed = True
    while changed:
        changed = False
        out = []
        while boxes:
            c = boxes.pop(0)
            merged = False
            for o in out:
                if (c[0] - dist < o[2] and o[0] - dist < c[2] and
                        c[1] - dist < o[3] and o[1] - dist < c[3]):
                    o[0] = min(o[0], c[0]); o[1] = min(o[1], c[1])
                    o[2] = max(o[2], c[2]); o[3] = max(o[3], c[3])
                    o[4] += c[4]
                    merged = changed = True
                    break
            if not merged:
                out.append(c)
        boxes = out
    return boxes


def groups(name: str, dist: int = 8, min_area: int = 400):
    _, mask = cutout(name)
    return merge_boxes(components(mask, min_area), dist)


def projection_splits(name: str, box, min_gap: int = 8, min_width: int = 30):
    """box 안에서 세로로 완전히 빈 열을 기준으로 좌→우 분할."""
    _, mask = cutout(name)
    x0, y0, x1, y1 = box[:4]
    cols = mask[y0:y1, x0:x1].any(axis=0)
    segs, start = [], None
    gap = 0
    for i, filled in enumerate(cols):
        if filled:
            if start is None:
                start = i
            gap = 0
        elif start is not None:
            gap += 1
            if gap >= min_gap:
                segs.append((start, i - gap + 1))
                start = None
    if start is not None:
        segs.append((start, len(cols)))
    segs = [(x0 + a, x0 + b) for a, b in segs if b - a >= min_width]
    out = []
    for a, b in segs:
        sub = mask[y0:y1, a:b]
        rows = np.where(sub.any(axis=1))[0]
        out.append([a, y0 + int(rows[0]), b, y0 + int(rows[-1]) + 1, 0])
    return out


def projection_splits_n(name: str, box, n: int, min_width: int = 30):
    """box 안을 좌→우로 정확히 n개로 나눈다. 가장 넓은 빈 열 구간 n-1개를 경계로 쓴다."""
    _, mask = cutout(name)
    x0, y0, x1, y1 = box[:4]
    filled = mask[y0:y1, x0:x1].any(axis=0)
    empty_runs, start = [], None
    for i, f in enumerate(filled):
        if not f and start is None:
            start = i
        elif f and start is not None:
            empty_runs.append((start, i))
            start = None
    if start is not None:
        empty_runs.append((start, len(filled)))
    inner = [r for r in empty_runs if r[0] > 0 and r[1] < len(filled)]
    inner.sort(key=lambda r: r[1] - r[0], reverse=True)
    cuts = sorted(set((a + b) // 2 for a, b in inner[:n - 1]))
    edges = [0] + cuts + [len(filled)]
    out = []
    for a, b in zip(edges, edges[1:]):
        if b - a < min_width:
            continue
        sub = mask[y0:y1, x0 + a:x0 + b]
        rows = np.where(sub.any(axis=1))[0]
        if rows.size == 0:
            continue
        out.append([x0 + a, y0 + int(rows[0]), x0 + b, y0 + int(rows[-1]) + 1, 0])
    return out


# ---------------------------------------------------------------- helpers
def crop_rgba(name: str, box):
    rgba, _ = cutout(name)
    x0, y0, x1, y1 = box[:4]
    pad = 2
    x0 = max(0, x0 - pad); y0 = max(0, y0 - pad)
    x1 = min(rgba.shape[1], x1 + pad); y1 = min(rgba.shape[0], y1 + pad)
    return Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")


def save(img: Image.Image, rel: str):
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    print(f"  saved {rel:38s} {img.size[0]:4d}x{img.size[1]:4d}  {os.path.getsize(path) // 1024:5d} KB")


def place(canvas: Image.Image, sprite: Image.Image, box) -> None:
    """box=(x0,y0,x1,y1) 안에 비율 유지하며 가운데 정렬해 붙인다."""
    bw, bh = box[2] - box[0], box[3] - box[1]
    s = min(bw / sprite.width, bh / sprite.height)
    w, h = max(1, int(sprite.width * s)), max(1, int(sprite.height * s))
    im = sprite.resize((w, h), Image.LANCZOS)
    x = box[0] + (bw - w) // 2
    y = box[1] + (bh - h) // 2
    canvas.alpha_composite(im, (x, y))


def pad_sprite(sprite: Image.Image, size, anchor="feet") -> Image.Image:
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    box = (0, 0, size[0], size[1] - 6) if anchor == "feet" else (0, 0, size[0], size[1])
    place(canvas, sprite, box)
    return canvas


def dbg_dump(name: str, boxes, fname: str):
    if not DEBUG:
        return
    rgba, _ = cutout(name)
    im = Image.fromarray(rgba, "RGBA")
    flat = Image.new("RGB", im.size, (255, 0, 255))
    flat.paste(im, (0, 0), im)
    d = ImageDraw.Draw(flat)
    for i, b in enumerate(boxes):
        d.rectangle([b[0], b[1], b[2] - 1, b[3] - 1], outline=(255, 0, 0), width=3)
        d.text((b[0] + 6, b[1] + 6), str(i), fill=(0, 0, 255))
    flat.save(os.path.join(ROOT, "..", "tmp", fname))


# ---------------------------------------------------------------- pipelines
def slice_shopkeeper():
    """4x3 걷기 시트 → 균일 셀 스프라이트시트(각 칸 중앙·발끝 정렬)."""
    name = "hanok_shopkeeper_walk_sheet"
    _, mask = cutout(name)
    h, w = mask.shape
    cols, rows = 4, 3
    cw, ch = w / cols, h / rows

    frames = [[None] * cols for _ in range(rows)]
    # 셀 경계의 미세 노이즈를 피하려고 '큰 연결 성분'만 프레임으로 쓴다.
    pieces = components(mask, 12000)
    assert len(pieces) == cols * rows, pieces
    for b in pieces:
        cx = (b[0] + b[2]) / 2.0
        cy = (b[1] + b[3]) / 2.0
        frames[min(rows - 1, int(cy // ch))][min(cols - 1, int(cx // cw))] = b
    flat = [f for row in frames for f in row]
    assert all(f is not None for f in flat), frames
    dbg_dump(name, flat, "dbg_shopkeeper.png")

    max_w = max(f[2] - f[0] for f in flat)
    max_h = max(f[3] - f[1] for f in flat)
    cell_w, cell_h = max_w + 10, max_h + 10

    sheet = Image.new("RGBA", (cell_w * cols, cell_h * rows), (0, 0, 0, 0))
    for i, f in enumerate(flat):
        sp = crop_rgba(name, f)
        r_, c_ = divmod(i, cols)
        x = c_ * cell_w + (cell_w - sp.width) // 2
        y = (r_ + 1) * cell_h - 6 - sp.height
        sheet.alpha_composite(sp, (x, y))
    save(sheet, "assets/sprites/shopkeeper_walk.png")
    print(f"  cell: {cell_w}x{cell_h}")


def slice_animals():
    name = "hanok_animals_3_customers"
    _, mask = cutout(name)
    boxes = merge_boxes(components(mask, 5000), 4)
    boxes = sorted(boxes, key=lambda b: b[0])
    dbg_dump(name, boxes, "dbg_animals.png")
    assert len(boxes) == 3, boxes
    names = ["customer_fox", "customer_cat", "customer_duck"]
    sprites = [crop_rgba(name, b) for b in boxes]
    cw = max(s.width for s in sprites) + 8
    ch = max(s.height for s in sprites) + 8
    for n, sp in zip(names, sprites):
        save(pad_sprite(sp, (cw, ch)), f"assets/sprites/{n}.png")


def slice_props():
    name = "hanok_counter_and_props_v3"
    boxes = groups(name, dist=6)
    dbg_dump(name, boxes, "dbg_props.png")
    assert len(boxes) == 4, boxes
    # 좌상=카운터 / 우상=절구 / 좌하=찜기 / 우하=다기
    boxes = sorted(boxes, key=lambda b: (0 if (b[1] + b[3]) / 2 < 560 else 1,
                                         (b[0] + b[2]) / 2))
    names = ["hanok_counter", "stone_mortar", "bamboo_steamer", "tea_set"]
    for n, b in zip(names, boxes):
        save(crop_rgba(name, b), f"assets/sprites/{n}.png")


def slice_icons():
    name = "hanok_stage1_icons_6_v2"
    boxes = groups(name, dist=8)
    dbg_dump(name, boxes, "dbg_icons.png")
    assert len(boxes) == 6, boxes
    boxes = sorted(boxes, key=lambda b: (0 if (b[1] + b[3]) / 2 < 560 else 1,
                                         (b[0] + b[2]) / 2))
    names = ["mugwort", "rice", "green_tea", "mugwort_injeolmi", "songpyeon", "yakgwa"]
    for n, b in zip(names, boxes):
        save(crop_rgba(name, b), f"assets/icons/{n}.png")


def slice_yard():
    name = "hanok_stage1_yard_props"
    boxes = groups(name, dist=8)
    dbg_dump(name, boxes, "dbg_yard.png")
    assert len(boxes) == 4, boxes
    boxes = sorted(boxes, key=lambda b: (0 if (b[1] + b[3]) / 2 < 700 else 1,
                                         (b[0] + b[2]) / 2))
    names = ["planter_mugwort", "planter_rice", "stepping_stones", "fence_flowers"]
    for n, b in zip(names, boxes):
        save(crop_rgba(name, b), f"assets/sprites/{n}.png")


def slice_ui():
    name = "hanok_stage1_ui_set"
    _, mask = cutout(name)
    all_boxes = groups(name, dist=8)
    dbg_dump(name, all_boxes, "dbg_ui.png")
    save(crop_rgba(name, _merge_pick(all_boxes, 0, 100, 400)), "assets/ui/hud_coin_bar.png")
    save(crop_rgba(name, _merge_pick(all_boxes, 1, 100, 400)), "assets/ui/hud_heart_bar.png")
    save(crop_rgba(name, _merge_pick(all_boxes, 0, 400, 900)), "assets/ui/speech_bubble.png")

    # 하단 4개 원형 버튼: y 900~ 영역을 세로 빈 열로 분할
    bottom = [b for b in all_boxes if b[1] > 860]
    band = [min(b[0] for b in bottom), min(b[1] for b in bottom),
            max(b[2] for b in bottom), max(b[3] for b in bottom)]
    btns = projection_splits_n(name, band, 4)
    dbg_dump(name, btns, "dbg_ui_buttons.png")
    assert len(btns) == 4, btns
    names = ["btn_book", "btn_tteok", "btn_tea", "btn_decor"]
    for n, b in zip(names, btns):
        save(crop_rgba(name, b), f"assets/ui/{n}.png")


def _merge_pick(boxes, idx, y_min, y_max):
    """y 대역 안에 있는 박스들 중 왼쪽부터 idx번째."""
    band = sorted([b for b in boxes if y_min <= b[1] <= y_max], key=lambda b: b[0])
    return band[idx]


def tiles():
    for src, rel in [("hanok_ground_grass_seamless", "assets/tiles/grass_tile.png"),
                     ("hanok_ground_dirt_seamless", "assets/tiles/dirt_tile.png")]:
        im = Image.open(os.path.join(SRC, src + ".png")).convert("RGB")
        save(im.resize((512, 512), Image.LANCZOS), rel)
    courtyard()


def courtyard():
    """흙마당: 타일을 깔고 가장자리를 부드럽고 불규칙하게 깎아 만든 1080x940 마당."""
    tile = Image.open(os.path.join(SRC, "hanok_ground_dirt_seamless.png")).convert("RGB")
    W, H = 1080, 940
    base = Image.new("RGB", (W, H))
    for y in range(0, H, tile.height):
        for x in range(0, W, tile.width):
            base.paste(tile, (x, y))
    base = base.resize((W, H))

    rng = np.random.default_rng(7)
    # 알파 마스크: 위/아래 가장자리는 물결치게, 좌우는 화면 밖까지
    yy = np.arange(H, dtype=np.float32)[:, None]
    noise = ndimage.gaussian_filter(rng.normal(size=(H, 1)).astype(np.float32), 26)
    noise = noise / max(1e-6, np.abs(noise).max())
    top = 26 + noise * 22
    bot = H - 30 + ndimage.gaussian_filter(rng.normal(size=(H, 1)).astype(np.float32), 20)[::-1] * 0
    a = np.clip((yy - top) / 26.0, 0, 1)
    a = np.minimum(a, np.clip((H - 26 - yy) / 26.0, 0, 1))
    a = np.repeat(a, W, axis=1)
    # 좌우 끝 살짝 투명
    xx = np.arange(W, dtype=np.float32)[None, :]
    a = np.minimum(a, np.clip(xx / 18.0, 0, 1) * np.clip((W - xx) / 18.0, 0, 1))
    rgba = np.dstack([np.array(base), np.clip(a * 255, 0, 255).astype(np.uint8)])
    save(Image.fromarray(rgba, "RGBA"), "assets/tiles/courtyard.png")


def shadow():
    """캐릭터 발밑 소프트 그림자 (검정 방사형)."""
    S = 256
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    cx = cy = (S - 1) / 2
    d = np.sqrt(((x - cx) / (S * 0.48)) ** 2 + ((y - cy) / (S * 0.30)) ** 2)
    a = np.clip(1.0 - d, 0, 1) ** 1.6
    rgba = np.zeros((S, S, 4), dtype=np.uint8)
    rgba[..., 3] = (a * 190).astype(np.uint8)
    img = Image.fromarray(rgba, "RGBA").filter(ImageFilter.GaussianBlur(3))
    save(img, "assets/sprites/shadow.png")


def icon():
    counter = Image.open(os.path.join(OUT, "assets/sprites/hanok_counter.png")).convert("RGBA")
    S = 512
    canvas = Image.new("RGBA", (S, S), (250, 240, 219, 255))
    place(canvas, counter, (36, 70, S - 36, S - 60))
    canvas.convert("RGB").save(os.path.join(OUT, "icon.png"), optimize=True)
    print(f"  saved icon.png")


def main():
    os.makedirs(os.path.join(OUT, "assets"), exist_ok=True)
    print("[1/8] 상인 걷기 시트")
    slice_shopkeeper()
    print("[2/8] 동물 손님")
    slice_animals()
    print("[3/8] 카운터/도구")
    slice_props()
    print("[4/8] 재료·음식 아이콘")
    slice_icons()
    print("[5/8] 마당 소품")
    slice_yard()
    print("[6/8] UI 세트")
    slice_ui()
    print("[7/8] 바닥 타일")
    tiles()
    print("[8/8] 그림자 · 아이콘")
    shadow()
    icon()
    print("done.")


if __name__ == "__main__":
    main()
