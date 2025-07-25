# PSD → Aseprite Import Script

> **Dedicated Lua script** to re-import PSD files that were previously exported  
> using **Export as psd.lua** (Aseprite → PSD) back into Aseprite.

![Requires Aseprite 1.3+](https://img.shields.io/badge/Requires-Aseprite%201.3%2B-blue)
![Lua 5.3](https://img.shields.io/badge/Lua-5.3-blue)
![MIT License](https://img.shields.io/badge/License-MIT-green)

---

## Key Features

| Feature | Description |
|---------|-------------|
| **RGB / RGBA (8 bpc) Support** | Recognizes both 3-channel (RGB) and 4-channel (RGBA) formats; automatically generates opaque alpha if missing |
| **Perfect Group Structure Restoration** | Interprets PSD `lsct` (Section Divider) Types 0-3 → Converts to Aseprite folders with `Layer.isGroup = true` |
| **PackBits RLE Decompression** | Implements only the compression used by the export script, reducing complexity while increasing speed |
| **UTF-8 Safe Name Handling** | Converts `luni` (UTF-16BE) layer names → UTF-8, automatically replaces invalid bytes to prevent crashes |
| **CLI & GUI Support** | Both Aseprite UI dialog and `aseprite -b -script ... --filename=…` command-line usage |
| **Automatic Debug Logging** | Generates `PSD Import Debug Log.txt` in the same folder for layer tree and error tracking |

---

## Requirements

* **Aseprite ≥ 1.2.10-beta3** (API v1 or higher)
* Lua 5.3 (built-in)
* Tested on: Windows 10 / macOS 13 / Ubuntu 22.04

---

## Installation

1. Copy **`import from psd.lua`** to:  
   `Aseprite ▶ File ▶ Scripts ▶ Open Scripts Folder`
2. Restart Aseprite or use **`Scripts ▶ Rescan Scripts Folder`**
3. If you see **`File ▶ Scripts ▶ import from psd`** in the menu, installation is complete

---

## Usage

### GUI Mode

1. Select **Scripts ▶ import from psd**
2. Choose your `.psd` file → Click **Import**
3. The imported sprite will open in a new tab


---

## Support Coverage / Limitations

| Item | Status |
|------|--------|
| 8 bpc Bit Depth | ✔ |
| RGB Color Mode | ✔ |
| Alpha Channel (-1) | ✔ (Auto-opaque if missing) |
| Group (Folder) Hierarchy | ✔ |
| Layer Masks | ✖ Ignored |
| Adjustment/Text Layers | ✖ Ignored (not rasterized) |
| 16/32 bpc, CMYK, etc. | ✖ Not supported |

---

## Known Issues

- **Large PSD files (hundreds of MB)**: Memory usage may increase significantly when PackBits compression is absent or when decompressed data is very large.

- **Surrogate pairs (U+10000+)**: Rarely used in PSD spec, but will be replaced with "?" if encountered.

---

## Contributing

Issues and Pull Requests are welcome! 📬

Please attach sample PSD files for bug reproduction or Sentry logs when reporting issues.

---

## License

[MIT License](https://github.com/Tin-01/aseprite-psd-scripts/blob/main/LICENSE) — Feel free to use, modify, and distribute while maintaining the license text and copyright notice.

---

## References

- [Aseprite API Documentation](https://github.com/aseprite/api)
- [Adobe Photoshop File Formats Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)
- [Export as psd.lua](https://github.com/Tsukina-7mochi/aseprite-scripts/tree/master/psd) (companion export script)
- [LayerVault: Anatomy of a PSD](https://github.com/layervault/psd.rb)
