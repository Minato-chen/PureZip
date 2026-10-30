import os
import sys
import wave
import math
import struct
import json
import zipfile
import tarfile
import subprocess
from PIL import Image, ImageDraw, ImageFont

BASE_DIR = "/Users/minato/Desktop/PureZip_TestFiles"

def make_dirs():
    os.makedirs(f"{BASE_DIR}/01_Documents_文档/Office", exist_ok=True)
    os.makedirs(f"{BASE_DIR}/01_Documents_文档/PDF", exist_ok=True)
    os.makedirs(f"{BASE_DIR}/01_Documents_文档/Text_and_Markdown", exist_ok=True)
    os.makedirs(f"{BASE_DIR}/01_Documents_文档/Structured_Data", exist_ok=True)

    os.makedirs(f"{BASE_DIR}/02_Media_多媒体/Images", exist_ok=True)
    os.makedirs(f"{BASE_DIR}/02_Media_多媒体/Audio", exist_ok=True)
    os.makedirs(f"{BASE_DIR}/02_Media_多媒体/Video", exist_ok=True)

    os.makedirs(f"{BASE_DIR}/03_Development_源码与工程/Swift_Project/Sources", exist_ok=True)
    os.makedirs(f"{BASE_DIR}/03_Development_源码与工程/Web_Frontend", exist_ok=True)
    os.makedirs(f"{BASE_DIR}/03_Development_源码与工程/Python_Module", exist_ok=True)
    os.makedirs(f"{BASE_DIR}/03_Development_源码与工程/Scripts_and_Executables", exist_ok=True)
    os.makedirs(f"{BASE_DIR}/03_Development_源码与工程/Dotfiles_隐藏配置", exist_ok=True)

    os.makedirs(f"{BASE_DIR}/04_Nested_Archives_嵌套压缩包", exist_ok=True)
    os.makedirs(f"{BASE_DIR}/05_Deep_Hierarchy_多层嵌套测试/Level_1/Level_2/Level_3/Level_4/Level_5", exist_ok=True)
    os.makedirs(f"{BASE_DIR}/06_Special_Names_特殊字符与边界测试", exist_ok=True)

def generate_text_files():
    # README.md
    readme_content = """# PureZip 综合功能测试套件 (Test Suite)

本目录包含完整的、真实有效的文件样本，专为测试 macOS 归档解压、悬浮预览 (Hover Preview)、快速预览 (QuickLook)、多层级解压以及拖拽导出设计。

## 目录索引
1. `01_Documents_文档/`: 办公文档 (DOCX, XLSX), 矢量 PDF, 富文本 RTF, Markdown, 配置数据 (JSON, YAML, CSV, XML, Plist)
2. `02_Media_多媒体/`: 真实图像 (PNG, JPG, WebP, GIF, SVG, ICO), 音频 (M4A, WAV, AIFF), 视频 (MP4)
3. `03_Development_源码与工程/`: Swift, Web (HTML/CSS/JS), Python, 可执行脚本, 隐藏文件
4. `04_Nested_Archives_嵌套压缩包/`: 嵌套 ZIP 与 TAR.GZ (用于测试包内递归浏览)
5. `05_Deep_Hierarchy_多层嵌套测试/`: 5 层深度递归目录结构
6. `06_Special_Names_特殊字符与边界测试/`: 中日文、Emoji 命名、空文件与大文件 (5MB)

## 测试场景矩阵
| 测试类别 | 目标文件 | 预期行为 |
| :--- | :--- | :--- |
| **悬浮预览** | `photo_sample.jpg` | 鼠标悬停 0.15s 弹出 HUD 大图预览 |
| **PDF 预览** | `PureZip_User_Manual.pdf` | 悬停即时渲染 PDF 矢量第 1 页 |
| **拖拽导出** | 任意单文件/目录 | 拖拽至桌面或 Finder，后台异步提取无卡顿 |
| **嵌套解压** | `inner_archive.zip` | 双击进入嵌套压缩包，支持面包屑返回 |
| **特殊字符** | `📁Emoji_🚀Rocket_🎉Party.json` | 编码正确解析，无乱码 |
"""
    with open(f"{BASE_DIR}/01_Documents_文档/Text_and_Markdown/README.md", "w", encoding="utf-8") as f:
        f.write(readme_content)

    with open(f"{BASE_DIR}/01_Documents_文档/Text_and_Markdown/CHANGELOG.txt", "w", encoding="utf-8") as f:
        f.write("PureZip Version History\n=======================\nv1.0.0 (2026-10-24)\n- Initial release with native 7z/libarchive\n- Hover preview & Finder drag-and-drop\n")

    with open(f"{BASE_DIR}/01_Documents_文档/Text_and_Markdown/LICENSE_MIT.txt", "w", encoding="utf-8") as f:
        f.write("MIT License\n\nCopyright (c) 2026 PureZip Contributors\n\nPermission is hereby granted, free of charge...\n")

    rtf_content = r"{\rtf1\ansi\ansicpg1252\deff0\nouicompat\deflang1033{\fonttbl{\f0\fnil\fcharset0 Helvetica;}}{\colortbl ;\red230\green126\blue34;\red41\green128\blue185;}\viewkind4\uc1 \pard\sa200\sl276\slmult1\b\fs32\cf1 PureZip RTF Document\b0\fs24\cf0\par This is a \i real formatted Rich Text Format (RTF)\i0  document used to verify document previews and quicklook generators in macOS.\par \cf2 Status: Verified\cf0\par}"
    with open(f"{BASE_DIR}/01_Documents_文档/Text_and_Markdown/Rich_Text_Note.rtf", "w", encoding="utf-8") as f:
        f.write(rtf_content)

def generate_structured_data():
    # JSON
    data = {
        "appName": "PureZip",
        "version": "1.1.4",
        "build": 255,
        "author": "minato",
        "features": {
            "hoverPreview": True,
            "systemQuickLook": True,
            "dragAndDrop": True,
            "pureCapsule": True,
            "pureDesk": True
        },
        "supportedFormats": ["zip", "7z", "tar", "gz", "bz2", "xz", "rar", "dmg", "iso"]
    }
    with open(f"{BASE_DIR}/01_Documents_文档/Structured_Data/configuration.json", "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    # CSV
    csv_content = "ID,Name,Type,CompressedSize,UncompressedSize,Status\n1,README.md,Text,1204,3420,Normal\n2,banner.png,Image,45890,128900,Encrypted\n3,bundle.zip,Archive,1048576,2097152,Valid\n"
    with open(f"{BASE_DIR}/01_Documents_文档/Structured_Data/users_database.csv", "w", encoding="utf-8") as f:
        f.write(csv_content)

    # XML
    xml_content = """<?xml version="1.0" encoding="UTF-8"?>
<PureZipProject build="20261025">
    <Metadata>
        <Name>PureZip Test Dataset</Name>
        <Category>Verification</Category>
    </Metadata>
    <Engines>
        <Engine name="SevenZip" priority="1" enabled="true"/>
        <Engine name="LibArchive" priority="2" enabled="true"/>
    </Engines>
</PureZipProject>
"""
    with open(f"{BASE_DIR}/01_Documents_文档/Structured_Data/catalog.xml", "w", encoding="utf-8") as f:
        f.write(xml_content)

    # YAML
    yaml_content = """version: '3.8'
services:
  purezip-core:
    image: purezip/runtime:latest
    container_name: purezip_test
    environment:
      - ENVIRONMENT=production
      - LOG_LEVEL=debug
    volumes:
      - ./staged:/var/data/archives:ro
    restart: unless-stopped
"""
    with open(f"{BASE_DIR}/01_Documents_文档/Structured_Data/docker-compose.yaml", "w", encoding="utf-8") as f:
        f.write(yaml_content)

    # Info.plist
    plist_content = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.minato.purezip.TestData</string>
    <key>CFBundleName</key>
    <string>PureZipTestData</string>
    <key>CFBundleVersion</key>
    <string>1.1.4</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.4</string>
</dict>
</plist>
"""
    with open(f"{BASE_DIR}/01_Documents_文档/Structured_Data/Info.plist", "w", encoding="utf-8") as f:
        f.write(plist_content)

def generate_office_docs():
    # Valid minimal DOCX (a zip archive with OOXML structure)
    docx_path = f"{BASE_DIR}/01_Documents_文档/Office/Sample_Document.docx"
    with zipfile.ZipFile(docx_path, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>""")
        z.writestr("_rels/.rels", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>""")
        z.writestr("word/document.xml", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>PureZip Verification Document (DOCX)</w:t></w:r></w:p>
    <w:p><w:r><w:t>This is a real Microsoft Word .docx format file generated for testing archive extraction and preview capabilities.</w:t></w:r></w:p>
  </w:body>
</w:document>""")

    # Valid minimal XLSX
    xlsx_path = f"{BASE_DIR}/01_Documents_文档/Office/Financial_Report.xlsx"
    with zipfile.ZipFile(xlsx_path, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
</Types>""")
        z.writestr("_rels/.rels", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>""")
        z.writestr("xl/workbook.xml", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheets><sheet name="Sheet1" sheetId="1" r:id="rId1" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/></sheets>
</workbook>""")

def generate_pdf():
    # Valid PDF with page, text, and vector graphics
    pdf_content = b"""%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>
endobj
4 0 obj
<< /Length 210 >>
stream
BT
/F1 24 Tf
50 720 Td
(PureZip Test Document - PDF) Tj
0 -40 Td
/F1 14 Tf
(This is a valid vector PDF document with text stream.) Tj
0 -30 Td
(It is designed to trigger PureZip's Hover Preview and QuickLook.) Tj
ET
0.2 0.5 0.9 rg
50 550 512 80 re
f
endstream
endobj
5 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
endobj
xref
0 6
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
0000000244 00000 n 
0000000508 00000 n 
trailer
<< /Size 6 /Root 1 0 R >>
startxref
577
%%EOF
"""
    with open(f"{BASE_DIR}/01_Documents_文档/PDF/PureZip_User_Manual.pdf", "wb") as f:
        f.write(pdf_content)

def generate_images():
    # 1. PNG with gradient & shapes
    img_png = Image.new("RGBA", (600, 400), (30, 32, 40, 255))
    draw = ImageDraw.Draw(img_png)
    for y in range(400):
        color = (int(30 + y * 0.1), int(45 + y * 0.3), int(80 + y * 0.4), 255)
        draw.line([(0, y), (600, y)], fill=color)
    draw.rounded_rectangle([40, 40, 560, 360], radius=20, outline=(255, 180, 20, 255), width=4)
    draw.ellipse([80, 80, 200, 200], fill=(240, 100, 40, 220))
    draw.rectangle([250, 100, 520, 140], fill=(255, 255, 255, 230))
    draw.rectangle([250, 170, 480, 200], fill=(200, 200, 200, 200))
    img_png.save(f"{BASE_DIR}/02_Media_多媒体/Images/graphic_banner.png", "PNG")

    # 2. JPG
    img_jpg = Image.new("RGB", (640, 480), (245, 245, 245))
    draw_jpg = ImageDraw.Draw(img_jpg)
    draw_jpg.rectangle([0, 0, 640, 240], fill=(70, 130, 180))
    draw_jpg.rectangle([0, 240, 640, 480], fill=(34, 139, 34))
    draw_jpg.ellipse([450, 40, 570, 160], fill=(255, 215, 0))
    img_jpg.save(f"{BASE_DIR}/02_Media_多媒体/Images/photo_sample.jpg", "JPEG", quality=92)

    # 3. WebP
    img_png.save(f"{BASE_DIR}/02_Media_多媒体/Images/modern_format.webp", "WEBP", quality=90)

    # 4. GIF Animated (3 frames)
    frames = []
    for i in range(5):
        frame = Image.new("RGB", (200, 200), (20 + i*40, 40 + i*30, 90))
        d = ImageDraw.Draw(frame)
        d.ellipse([50 + i*10, 50, 100 + i*10, 100], fill=(255, 220, 0))
        frames.append(frame)
    frames[0].save(f"{BASE_DIR}/02_Media_多媒体/Images/animation_test.gif", save_all=True, append_images=frames[1:], duration=200, loop=0)

    # 5. SVG
    svg_content = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" width="100%" height="100%">
  <defs>
    <linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#FF9900;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#FF5500;stop-opacity:1" />
    </linearGradient>
  </defs>
  <rect width="400" height="400" rx="60" fill="url(#grad)"/>
  <circle cx="200" cy="180" r="80" fill="#ffffff" opacity="0.9"/>
  <polygon points="170,140 250,180 170,220" fill="#FF5500"/>
  <text x="200" y="320" font-family="-apple-system, sans-serif" font-size="28" font-weight="bold" fill="#ffffff" text-anchor="middle">PureZip Vector</text>
</svg>"""
    with open(f"{BASE_DIR}/02_Media_多媒体/Images/logo_vector.svg", "w", encoding="utf-8") as f:
        f.write(svg_content)

    # 6. ICO
    img_ico = Image.new("RGBA", (64, 64), (255, 140, 0, 255))
    d_ico = ImageDraw.Draw(img_ico)
    d_ico.rectangle([10, 10, 54, 54], fill=(255, 255, 255, 255))
    img_ico.save(f"{BASE_DIR}/02_Media_多媒体/Images/app_icon.ico", format="ICO")

def generate_audio():
    # 1. Generate real WAV using wave module (A4 440Hz sine wave, 2 seconds)
    wav_path = f"{BASE_DIR}/02_Media_多媒体/Audio/tone_440hz.wav"
    sample_rate = 44100
    duration = 2.0
    frequency = 440.0
    num_samples = int(sample_rate * duration)
    with wave.open(wav_path, "w") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        for i in range(num_samples):
            value = int(32767.0 * 0.5 * math.sin(2.0 * math.pi * frequency * (i / sample_rate)))
            data = struct.pack('<h', value)
            wav.writeframes(data)

    # 2. Use macOS 'say' and 'afconvert' to create a real voice M4A & AIFF audio file
    aiff_temp = f"{BASE_DIR}/02_Media_多媒体/Audio/voice_sample.aiff"
    m4a_path = f"{BASE_DIR}/02_Media_多媒体/Audio/voice_sample.m4a"
    try:
        subprocess.run(["say", "-o", aiff_temp, "Welcome to PureZip file preview test."], check=True)
        subprocess.run(["afconvert", aiff_temp, m4a_path, "-f", "m4af", "-d", "aac"], check=True)
    except Exception as e:
        print(f"Notice on audio generation: {e}")

def generate_video():
    # Use ffmpeg to generate a valid 2-second test MP4 video with color animation and text
    mp4_path = f"{BASE_DIR}/02_Media_多媒体/Video/sample_clip.mp4"
    cmd = [
        "/opt/homebrew/bin/ffmpeg",
        "-y",
        "-f", "lavfi",
        "-i", "testsrc=duration=2:size=640x360:rate=30",
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        mp4_path
    ]
    try:
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    except Exception as e:
        print(f"Notice on video generation: {e}")

def generate_code_projects():
    # Swift Project
    with open(f"{BASE_DIR}/03_Development_源码与工程/Swift_Project/Package.swift", "w", encoding="utf-8") as f:
        f.write("""// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SampleSwiftTool",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "sample-tool", targets: ["SampleSwiftTool"])],
    targets: [.executableTarget(name: "SampleSwiftTool")]
)
""")

    with open(f"{BASE_DIR}/03_Development_源码与工程/Swift_Project/Sources/Main.swift", "w", encoding="utf-8") as f:
        f.write("""import Foundation

@main
struct MainApp {
    static func main() {
        print("Hello from PureZip Sample Swift Project!")
    }
}
""")

    with open(f"{BASE_DIR}/03_Development_源码与工程/Swift_Project/Config.xcconfig", "w", encoding="utf-8") as f:
        f.write("PRODUCT_BUNDLE_IDENTIFIER = com.purezip.test.tool\nMACOSX_DEPLOYMENT_TARGET = 13.0\n")

    # Web Frontend
    html = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <title>PureZip Web Demo</title>
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <div class="card">
    <h1>🚀 PureZip Web 预览组件</h1>
    <p>这是一个包含标准 HTML5、CSS3 和 JavaScript 的前端工程包。</p>
    <button id="testBtn">点击交互</button>
  </div>
  <script src="app.js"></script>
</body>
</html>"""
    with open(f"{BASE_DIR}/03_Development_源码与工程/Web_Frontend/index.html", "w", encoding="utf-8") as f:
        f.write(html)

    css = """body {
  margin: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100vh;
  background: linear-gradient(135deg, #1f1c2c, #928dab);
  font-family: -apple-system, sans-serif;
}
.card {
  background: rgba(255, 255, 255, 0.15);
  backdrop-filter: blur(12px);
  padding: 30px 40px;
  border-radius: 16px;
  color: #fff;
  box-shadow: 0 8px 32px rgba(0,0,0,0.3);
}
button {
  background: #ff9900;
  border: none;
  padding: 10px 20px;
  border-radius: 8px;
  color: #fff;
  font-weight: bold;
  cursor: pointer;
}"""
    with open(f"{BASE_DIR}/03_Development_源码与工程/Web_Frontend/styles.css", "w", encoding="utf-8") as f:
        f.write(css)

    js = """document.getElementById('testBtn').addEventListener('click', () => {
  alert('PureZip 前端 JavaScript 逻辑正常执行！');
});"""
    with open(f"{BASE_DIR}/03_Development_源码与工程/Web_Frontend/app.js", "w", encoding="utf-8") as f:
        f.write(js)

    with open(f"{BASE_DIR}/03_Development_源码与工程/Web_Frontend/package.json", "w", encoding="utf-8") as f:
        f.write('{\n  "name": "purezip-web-test",\n  "version": "1.0.0",\n  "scripts": { "build": "echo build" }\n}\n')

    # Python
    with open(f"{BASE_DIR}/03_Development_源码与工程/Python_Module/script.py", "w", encoding="utf-8") as f:
        f.write('def compute_hash(data: str) -> str:\n    import hashlib\n    return hashlib.sha256(data.encode()).hexdigest()\n\nif __name__ == "__main__":\n    print("Hash:", compute_hash("PureZip"))\n')

    with open(f"{BASE_DIR}/03_Development_源码与工程/Python_Module/requirements.txt", "w", encoding="utf-8") as f:
        f.write("requests>=2.31.0\npillow>=10.0.0\npyyaml>=6.0\n")

    # Shell Scripts (+x executable)
    sh_path = f"{BASE_DIR}/03_Development_源码与工程/Scripts_and_Executables/install.sh"
    with open(sh_path, "w", encoding="utf-8") as f:
        f.write('#!/usr/bin/env bash\necho "Running PureZip automated self-test..."\necho "Complete!"\n')
    os.chmod(sh_path, 0o755)

    cmd_path = f"{BASE_DIR}/03_Development_源码与工程/Scripts_and_Executables/build_tool.command"
    with open(cmd_path, "w", encoding="utf-8") as f:
        f.write('#!/bin/bash\ncd "$(dirname "$0")"\necho "Build completed successfully."\n')
    os.chmod(cmd_path, 0o755)

    # Dotfiles
    with open(f"{BASE_DIR}/03_Development_源码与工程/Dotfiles_隐藏配置/.env", "w", encoding="utf-8") as f:
        f.write("API_KEY=test_purezip_secret_key_889911\nENV=sandbox\nPORT=8080\n")

    with open(f"{BASE_DIR}/03_Development_源码与工程/Dotfiles_隐藏配置/.gitignore", "w", encoding="utf-8") as f:
        f.write(".DS_Store\n.build/\n*.o\n*.tmp\nnode_modules/\n")

def generate_nested_archives():
    # 1. Inner zip archive
    inner_zip_path = f"{BASE_DIR}/04_Nested_Archives_嵌套压缩包/inner_archive.zip"
    with zipfile.ZipFile(inner_zip_path, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr("nested_welcome.txt", "恭喜你！成功在 PureZip 中双击进入了嵌套压缩包！\n你可以按 Back 键或面包屑导航返回上一级。\n")
        z.writestr("config/settings.json", json.dumps({"nestedDepth": 2, "verified": True}, indent=2))
        z.writestr("subfolder/inner_note.md", "# 嵌套层级 Markdown 说明\n此条目位于 inner_archive.zip 压缩包内部。")

    # 2. tar.gz archive
    tar_path = f"{BASE_DIR}/04_Nested_Archives_嵌套压缩包/bundled_logs.tar.gz"
    with tarfile.open(tar_path, "w:gz") as tar:
        temp_log = "/tmp/system_audit.log"
        with open(temp_log, "w", encoding="utf-8") as tf:
            tf.write("2026-10-25 00:01:10 [INFO] System initialized\n2026-10-25 00:01:12 [INFO] Archive Engine active\n")
        tar.add(temp_log, arcname="audit_2026/system_audit.log")

def generate_deep_hierarchy():
    deep_path = f"{BASE_DIR}/05_Deep_Hierarchy_多层嵌套测试/Level_1/Level_2/Level_3/Level_4/Level_5/deep_secret.txt"
    with open(deep_path, "w", encoding="utf-8") as f:
        f.write("恭喜！你成功展开并访问了第 5 级深层嵌套目录！\nPath: Level_1 -> Level_2 -> Level_3 -> Level_4 -> Level_5 -> deep_secret.txt\n")

def generate_special_cases():
    # Chinese name
    with open(f"{BASE_DIR}/06_Special_Names_特殊字符与边界测试/中文测试文档_含空格 与 标点.txt", "w", encoding="utf-8") as f:
        f.write("测试中文字符集与空格的文件名兼容性。\nPureZip 自动适配 UTF-8 编码以及 GBK 遗留 Windows 压缩包编码。\n")

    # Japanese name
    with open(f"{BASE_DIR}/06_Special_Names_特殊字符与边界测试/日本語のファイル名_テスト.md", "w", encoding="utf-8") as f:
        f.write("# 日本語ファイル名テスト\nShift-JIS および UTF-8 でエンコードされたアーカイブ名のテスト。\n")

    # Emoji name
    with open(f"{BASE_DIR}/06_Special_Names_特殊字符与边界测试/📁Emoji_🚀Rocket_🎉Party.json", "w", encoding="utf-8") as f:
        json.dump({"emoji": "🚀🎉📁", "supported": True}, f, indent=2, ensure_ascii=False)

    # Empty 0-byte file
    with open(f"{BASE_DIR}/06_Special_Names_特殊字符与边界测试/empty_zero_byte.empty", "wb") as f:
        pass

    # 5MB large file for performance & progress testing
    large_path = f"{BASE_DIR}/06_Special_Names_特殊字符与边界测试/large_sample_5mb.bin"
    chunk = b"PureZipBenchmarkDataPayload12345\n" * 160 # ~5KB
    with open(large_path, "wb") as f:
        for _ in range(1000): # ~5MB
            f.write(chunk)

if __name__ == "__main__":
    print(f"Creating comprehensive test files at: {BASE_DIR}")
    make_dirs()
    generate_text_files()
    generate_structured_data()
    generate_office_docs()
    generate_pdf()
    generate_images()
    generate_audio()
    generate_video()
    generate_code_projects()
    generate_nested_archives()
    generate_deep_hierarchy()
    generate_special_cases()
    print("SUCCESS: All test files generated successfully!")
