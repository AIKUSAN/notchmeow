#!/usr/bin/env python3
"""Writes NotchMeow's attachment test files into a directory (standard library only)."""
import os
import struct
import sys
import zipfile
import zlib


def pdf(objects):
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for i, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n".encode() + b"0000000000 65535 f \n"
    for off in offsets:
        out += f"{off:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return bytes(out)


def stream(extra, data):
    return b"<< " + extra + b" /Length " + str(len(data)).encode() + b" >>\nstream\n" + data + b"\nendstream"


CATALOG = b"<< /Type /Catalog /Pages 2 0 R >>"
PAGES = b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"

TEXT_PDF = pdf([
    CATALOG, PAGES,
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 144] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    stream(b"", b"BT /F1 18 Tf 20 70 Td (Hello from NotchMeow) Tj ET"),
])

SCAN_PDF = pdf([
    CATALOG, PAGES,
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << /XObject << /Im1 4 0 R >> >> /Contents 5 0 R >>",
    stream(b"/Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceGray /BitsPerComponent 8",
           bytes([0, 255, 255, 0])),
    stream(b"", b"q 100 0 0 100 0 0 cm /Im1 Do Q"),
])


def png_1x1():
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(b"\x00\xff\x80\x00\xff")) + chunk(b"IEND", b"")


DOCX_PARTS = {
    "[Content_Types].xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
    "_rels/.rels": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
    "word/document.xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>Shrimpy and Momo</w:t></w:r></w:p><w:p><w:r><w:t>live in the notch.</w:t></w:r></w:p></w:body></w:document>',
}

HTML = ("<html><head><style>p{}</style><script>var secret = 'hidden';</script></head>"
        "<body><p>Momo says <b>hi</b></p></body></html>")
RTF = r"{\rtf1\ansi\deff0 {\fonttbl {\f0 Helvetica;}}\f0 Plain RTF text.\par}"


def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)

    def write(name, data):
        with open(os.path.join(out_dir, name), "wb") as f:
            f.write(data if isinstance(data, bytes) else data.encode("utf-8"))

    write("note.txt", "Hello Shrimpy\nSecond line\n")
    write("code.swift", 'print("meow")\n')
    write("empty.txt", b"")
    write("text.pdf", TEXT_PDF)
    write("Upper.PDF", TEXT_PDF)
    write("scan.pdf", SCAN_PDF)
    write("photo.png", png_1x1())
    write("page.html", HTML)
    write("Legacy.HTM", HTML)
    write("doc.rtf", RTF)
    write("setup.exe", b"MZ" + bytes(62))
    write("blob.dat", b"\x00\x01\x02binary\x00")
    with zipfile.ZipFile(os.path.join(out_dir, "letter.docx"), "w", zipfile.ZIP_DEFLATED) as z:
        for name, xml in DOCX_PARTS.items():
            z.writestr(name, xml)
    with zipfile.ZipFile(os.path.join(out_dir, "archive.zip"), "w") as z:
        z.writestr("inside.txt", "packed")
    with open(os.path.join(out_dir, "big.txt"), "wb") as f:
        f.truncate(26214401)  # sparse: 1 byte over the 25 MB limit, takes no real disk space


if __name__ == "__main__":
    main(sys.argv[1])
