"""Generators for the demo component documents (PDF reports and PNG photos).

Every generated file is visibly marked as a DEMO document so it can never be
mistaken for a genuine certificate.
"""

from __future__ import annotations

import io
import random
import zlib
import textwrap
from datetime import date

from PIL import Image, ImageDraw, ImageFilter, ImageFont

DEMO_NOTICE = "DEMO DOCUMENT - generated sample data for the Open Digital Twin Platform. Not a real certificate."

# --------------------------------------------------------------------------- #
# Minimal PDF writer (single page, Helvetica, WinAnsi) - no external deps.
# --------------------------------------------------------------------------- #

_PDF_REPLACEMENTS = {"µε": "microstrain", "ε": "e", "–": "-", "—": "-", "Ø": "O", "≤": "<=", "≥": ">="}


def _pdf_text(value: str) -> str:
    for src, dst in _PDF_REPLACEMENTS.items():
        value = value.replace(src, dst)
    encoded = value.encode("cp1252", errors="replace").decode("cp1252")
    return encoded.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def build_pdf(title: str, subtitle: str, sections: list[tuple[str, list[str]]]) -> bytes:
    width, height = 595, 842  # A4 in points
    ops: list[str] = []

    def text(x: float, y: float, size: int, value: str, bold: bool = False, gray: float = 0.0) -> None:
        font = "F2" if bold else "F1"
        ops.append(f"BT {gray:.2f} g /{font} {size} Tf {x:.1f} {y:.1f} Td ({_pdf_text(value)}) Tj ET")

    # Header band
    ops.append("0.07 0.20 0.33 rg 0 772 595 70 re f")
    ops.append(f"BT 1 1 1 rg /F2 18 Tf 40 812 Td ({_pdf_text('OPEN DIGITAL TWIN PLATFORM')}) Tj ET")
    ops.append(f"BT 0.75 0.85 0.95 rg /F1 10 Tf 40 794 Td ({_pdf_text(subtitle)}) Tj ET")
    # Demo banner
    ops.append("0.99 0.93 0.80 rg 40 735 515 24 re f")
    ops.append(f"BT 0.55 0.30 0.00 rg /F2 8.5 Tf 48 744 Td ({_pdf_text(DEMO_NOTICE)}) Tj ET")

    y = 705.0
    for line in textwrap.wrap(title, 60):
        text(40, y, 16, line, bold=True)
        y -= 22
    y -= 6
    for heading, lines in sections:
        if y < 90:
            break
        ops.append(f"0.85 0.88 0.92 RG 0.8 w 40 {y + 4:.1f} m 555 {y + 4:.1f} l S")
        y -= 14
        text(40, y, 11, heading.upper(), bold=True, gray=0.15)
        y -= 16
        for raw in lines:
            for line in textwrap.wrap(raw, 95) or [""]:
                if y < 70:
                    break
                text(48, y, 9.5, line, gray=0.1)
                y -= 13.5
        y -= 8
    ops.append(f"BT 0.45 g /F1 8 Tf 40 40 Td ({_pdf_text('Generated ' + date.today().isoformat() + '  |  ' + DEMO_NOTICE)}) Tj ET")

    stream = "\n".join(ops).encode("cp1252", errors="replace")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width} {height}] "
            "/Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>"
        ).encode(),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
        b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"\nendstream",
    ]
    out = io.BytesIO()
    out.write(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for index, body in enumerate(objects, start=1):
        offsets.append(out.tell())
        out.write(f"{index} 0 obj\n".encode() + body + b"\nendobj\n")
    xref = out.tell()
    out.write(f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode())
    for off in offsets:
        out.write(f"{off:010d} 00000 n \n".encode())
    out.write(f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode())
    return out.getvalue()


# --------------------------------------------------------------------------- #
# PNG images
# --------------------------------------------------------------------------- #


def _font(size: int) -> ImageFont.ImageFont:
    for name in ("arial.ttf", "DejaVuSans.ttf", "Helvetica.ttc"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _png(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def build_xray_png(caption: str, section: str, seed: int) -> bytes:
    """Radiograph-style image of a wall section with two concealed pipes and fittings."""
    rng = random.Random(seed)
    w, h = 1280, 800
    img = Image.new("L", (w, h), 28)
    draw = ImageDraw.Draw(img)
    for _ in range(9000):  # aggregate / plaster grain
        x, y = rng.randrange(w), rng.randrange(h)
        v = rng.randint(30, 70)
        draw.point((x, y), fill=v)
    for bx in range(0, w, 160):  # brick joints
        draw.line([(bx, 0), (bx, h)], fill=44, width=3)
    for by in range(0, h, 90):
        draw.line([(0, by), (w, by)], fill=40, width=2)
    img = img.filter(ImageFilter.GaussianBlur(2.2))
    draw = ImageDraw.Draw(img)

    offset = 40 if section.upper().endswith("B") else 0
    hot_y, cold_y = 300 + offset, 420 + offset
    for y, width in ((hot_y, 34), (cold_y, 34)):
        draw.line([(60, y), (w - 260, y)], fill=210, width=width)
        draw.line([(60, y), (w - 260, y)], fill=245, width=8)
    for x in (60, w - 260):  # elbows / fittings
        draw.ellipse([x - 26, hot_y - 26, x + 26, hot_y + 26], fill=235)
        draw.ellipse([x - 26, cold_y - 26, x + 26, cold_y + 26], fill=235)
    draw.line([(w - 260, hot_y), (w - 260, h - 80)], fill=210, width=34)
    draw.line([(w - 200, cold_y), (w - 200, h - 80)], fill=210, width=34)
    draw.line([(w - 260, cold_y), (w - 200, cold_y)], fill=210, width=34)
    for x in range(140, w - 300, 220):  # pipe clips
        draw.rectangle([x, hot_y - 30, x + 12, cold_y + 30], fill=160)
    img = img.filter(ImageFilter.GaussianBlur(1.2)).convert("RGB")

    overlay = ImageDraw.Draw(img)
    f_big, f_small = _font(30), _font(20)
    overlay.rectangle([0, 0, w, 64], fill=(10, 18, 30))
    overlay.text((24, 16), f"X-RAY  |  {caption}  |  SECTION {section.upper()}", font=f_big, fill=(150, 220, 255))
    overlay.line([(40, h - 50), (240, h - 50)], fill=(255, 255, 255), width=4)
    overlay.text((40, h - 44), "200 mm", font=f_small, fill=(255, 255, 255))
    overlay.text((w - 560, h - 44), "DEMO IMAGE - generated sample radiograph", font=f_small, fill=(255, 190, 90))
    overlay.text((70, hot_y - 62), "HOT  PE-RT/AL 20 mm", font=f_small, fill=(255, 120, 100))
    overlay.text((70, cold_y + 30), "COLD PE-RT/AL 20 mm", font=f_small, fill=(120, 190, 255))
    return _png(img)


def build_site_photo_png(caption: str, seed: int) -> bytes:
    """Stylised fit-up photo of a steel block: plate field, weld seams, stiffeners."""
    rng = random.Random(seed)
    w, h = 1280, 800
    img = Image.new("RGB", (w, h), (92, 98, 106))
    draw = ImageDraw.Draw(img)
    horizon = 520
    for y in range(horizon):  # back bulkhead gradient
        shade = int(70 + 50 * y / horizon)
        draw.line([(0, y), (w, y)], fill=(shade, shade + 6, shade + 14))
    for x in range(80, w, 150):  # vertical stiffeners with perspective
        draw.polygon([(x, 40), (x + 26, 40), (x + 34, horizon), (x + 8, horizon)], fill=(140, 146, 154))
        draw.line([(x + 8, horizon), (x + 34, horizon)], fill=(240, 180, 80), width=3)
    for i in range(18):  # tank-top plating with weld seams in perspective
        y = horizon + (i * i) * 1.0 + i * 4
        draw.line([(0, y), (w, y)], fill=(110, 116, 124), width=1)
    for k in range(-6, 7):
        draw.line([(w / 2 + k * 40, horizon), (w / 2 + k * 260, h)], fill=(120, 124, 130), width=2)
    draw.line([(0, horizon + 60), (w, horizon + 60)], fill=(230, 170, 70), width=5)
    for _ in range(4000):
        x, y = rng.randrange(w), rng.randrange(h)
        c = rng.randint(-14, 14)
        r, g, b = img.getpixel((x, y))
        draw.point((x, y), fill=(max(0, r + c), max(0, g + c), max(0, b + c)))
    img = img.filter(ImageFilter.GaussianBlur(0.8))
    draw = ImageDraw.Draw(img)
    f_big, f_small = _font(30), _font(20)
    draw.rectangle([0, 0, w, 64], fill=(10, 18, 30))
    draw.text((24, 16), f"SITE PHOTO  |  {caption}", font=f_big, fill=(255, 255, 255))
    draw.text((w - 470, h - 40), "DEMO IMAGE - generated sample photo", font=f_small, fill=(255, 200, 90))
    return _png(img)


def build_document(row: dict, component: dict, project: dict) -> tuple[bytes, str]:
    """Return (bytes, content_type) for a documents row based on its path extension."""
    path: str = row["object_path"]
    title: str = row["title"]
    seed = sum(ord(ch) for ch in path)
    if path.lower().endswith(".png"):
        if component["mesh_node_id"] == "NODE_CONCEALED_PIPE_KITCHEN":
            section = "B" if "section_b" in path.lower() else "A"
            return build_xray_png(component["name"], section, seed), "image/png"
        return build_site_photo_png(title, seed), "image/png"

    meta = component.get("metadata") or {}
    doc_no = f"ODT-{row['doc_type'][:3].upper()}-{zlib.crc32(path.encode()) % 100000:05d}"
    sections: list[tuple[str, list[str]]] = [
        (
            "Document",
            [
                f"Document no.: {doc_no}",
                f"Type: {row['doc_type']}",
                f"Issued: {str(row.get('uploaded_at', ''))[:10]}",
            ],
        ),
        (
            "Asset",
            [
                f"Project: {project['name']} ({project['domain_type']})",
                f"Component: {component['name']}",
                f"mesh_node_id: {component['mesh_node_id']}",
                f"Category: {component.get('category') or '-'}",
                f"Material: {component.get('material') or '-'}",
                f"Weight: {component.get('weight_kg') or '-'} kg   Volume: {component.get('volume_m3') or '-'} m3",
            ],
        ),
        ("Technical data", [f"{k.replace('_', ' ').capitalize()}: {v}" for k, v in meta.items()]),
    ]
    findings = {
        "certificate": [
            "The component identified above was reviewed against the referenced specification.",
            "Result: CONFORMS (sample statement for demonstration purposes).",
        ],
        "inspection": [
            "Inspection scope: visual, dimensional and functional checks per project ITP.",
            "Result: see technical data and current component status in the twin.",
        ],
        "manual": [
            "1. Safety: isolate and lock out before maintenance.",
            "2. Routine checks: inspect fasteners, seals and connections at each service interval.",
            "3. Records: log all interventions against the mesh_node_id in the digital twin.",
        ],
        "photo": ["Photo record attached in the digital twin."],
    }[row["doc_type"]]
    sections.append(("Statement" if row["doc_type"] != "manual" else "Contents", findings))
    subtitle = f"{project['name']}  |  {component['mesh_node_id']}"
    return build_pdf(title, subtitle, sections), "application/pdf"
