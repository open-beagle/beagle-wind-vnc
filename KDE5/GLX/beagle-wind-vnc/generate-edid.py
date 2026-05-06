#!/usr/bin/env python3
"""
Generate a valid EDID binary for headless NVIDIA GPU environments.

Produces a 128-byte base EDID block that declares a virtual gaming monitor
supporting the specified refresh rate (30/60/120/144 Hz) at 1920x1080.

Usage:
    python3 generate-edid.py [REFRESH_RATE] [OUTPUT_PATH]
    python3 generate-edid.py 144 /etc/X11/edid.bin

The generated EDID mimics a gaming monitor with:
- Manufacturer: BWD (Beagle Wind Display)
- Preferred timing: 1920x1080 @ target refresh rate
- Pixel clock calculated via CVT-RB2 (Reduced Blanking v2) for high refresh
- Correct checksum (critical for NVIDIA driver acceptance)
"""

import sys
import struct


def cvt_rb2_timing(h_active, v_active, refresh):
    """
    Calculate CVT-RB2 (Reduced Blanking version 2) timing parameters.
    RB2 uses minimal blanking (80 pixels H-blank, 6 lines V-blank) for high refresh.
    """
    # CVT-RB2 constants
    h_blank = 80  # Fixed horizontal blanking for RB2
    v_blank_front = 1
    v_sync = 8  # RB2 uses 8-line vsync
    v_blank_back = 6 - v_sync - v_blank_front  # Minimum 6 lines total V-blank
    if v_blank_back < 1:
        v_blank_back = 1

    # For very high refresh rates, we need more V-blank
    # RB2 spec: V_BLANK = max(460/H_PERIOD, RB_MIN_V_BLANK)
    h_total = h_active + h_blank
    h_period_us = 1000000.0 / (refresh * (v_active + 6))  # approximate
    min_vblank_from_spec = int(460.0 / h_period_us + 0.5)
    v_blank_total = max(6, min_vblank_from_spec)

    v_blank_front = 1
    v_blank_back = v_blank_total - v_sync - v_blank_front

    v_total = v_active + v_blank_front + v_sync + v_blank_back
    h_total = h_active + h_blank

    pixel_clock_khz = int(h_total * v_total * refresh / 1000.0 + 0.5)

    return {
        'h_active': h_active,
        'v_active': v_active,
        'h_blank': h_blank,
        'v_blank_front': v_blank_front,
        'v_sync': v_sync,
        'v_blank_back': v_blank_back,
        'h_total': h_total,
        'v_total': v_total,
        'pixel_clock_khz': pixel_clock_khz,
        'refresh': refresh,
    }


def encode_dtd(timing):
    """Encode a Detailed Timing Descriptor (18 bytes) from timing parameters."""
    pclk = timing['pixel_clock_khz']
    h_active = timing['h_active']
    h_blank = timing['h_blank']
    v_active = timing['v_active']
    v_blank = timing['v_blank_front'] + timing['v_sync'] + timing['v_blank_back']

    # H/V sync offset and width (RB2: sync at front porch start)
    h_sync_offset = 8  # RB2 standard
    h_sync_width = 32  # RB2 standard
    v_sync_offset = timing['v_blank_front']
    v_sync_width = timing['v_sync']

    dtd = bytearray(18)

    # Bytes 0-1: Pixel clock in 10 kHz units (little-endian)
    pclk_10khz = pclk // 10
    dtd[0] = pclk_10khz & 0xFF
    dtd[1] = (pclk_10khz >> 8) & 0xFF

    # Byte 2: H active lower 8 bits
    dtd[2] = h_active & 0xFF
    # Byte 3: H blanking lower 8 bits
    dtd[3] = h_blank & 0xFF
    # Byte 4: H active upper 4 | H blanking upper 4
    dtd[4] = ((h_active >> 8) & 0x0F) << 4 | ((h_blank >> 8) & 0x0F)

    # Byte 5: V active lower 8 bits
    dtd[5] = v_active & 0xFF
    # Byte 6: V blanking lower 8 bits
    dtd[6] = v_blank & 0xFF
    # Byte 7: V active upper 4 | V blanking upper 4
    dtd[7] = ((v_active >> 8) & 0x0F) << 4 | ((v_blank >> 8) & 0x0F)

    # Byte 8: H sync offset lower 8 bits
    dtd[8] = h_sync_offset & 0xFF
    # Byte 9: H sync width lower 8 bits
    dtd[9] = h_sync_width & 0xFF
    # Byte 10: V sync offset lower 4 | V sync width lower 4
    dtd[10] = ((v_sync_offset & 0x0F) << 4) | (v_sync_width & 0x0F)
    # Byte 11: H sync offset[9:8] | H sync width[9:8] | V sync offset[5:4] | V sync width[5:4]
    dtd[11] = (((h_sync_offset >> 8) & 0x03) << 6 |
               ((h_sync_width >> 8) & 0x03) << 4 |
               ((v_sync_offset >> 4) & 0x03) << 2 |
               ((v_sync_width >> 4) & 0x03))

    # Bytes 12-13: H/V image size in mm (531x298 for 24" 16:9)
    h_size_mm = 531
    v_size_mm = 298
    dtd[12] = h_size_mm & 0xFF
    dtd[13] = v_size_mm & 0xFF
    dtd[14] = ((h_size_mm >> 8) & 0x0F) << 4 | ((v_size_mm >> 8) & 0x0F)

    # Byte 15: H border (0)
    dtd[15] = 0
    # Byte 16: V border (0)
    dtd[16] = 0

    # Byte 17: Flags - Digital separate sync, H+/V+ (positive polarity)
    # Bit 7: interlaced (0=no)
    # Bits 6-5: stereo (00=none)
    # Bits 4-3: sync type (11=digital separate)
    # Bit 2: V sync polarity (1=positive)
    # Bit 1: H sync polarity (1=positive)
    dtd[17] = 0b00011110  # Non-interlaced, digital separate, H+/V+

    return dtd


def make_monitor_range_descriptor(min_v, max_v, min_h, max_h, max_pclk_mhz):
    """Create a Monitor Range Limits descriptor (18 bytes)."""
    desc = bytearray(18)
    desc[0] = 0x00
    desc[1] = 0x00
    desc[2] = 0x00
    desc[3] = 0xFD  # Monitor Range Limits tag
    desc[4] = 0x00  # No flags (offsets not used)
    desc[5] = min_v & 0xFF       # Min V rate Hz
    desc[6] = max_v & 0xFF       # Max V rate Hz
    desc[7] = min_h & 0xFF       # Min H rate kHz
    desc[8] = max_h & 0xFF       # Max H rate kHz
    desc[9] = max_pclk_mhz // 10  # Max pixel clock / 10 MHz
    desc[10] = 0x01  # GTF secondary curve not supported (default timing)
    desc[11] = 0x0A  # Line feed
    # Bytes 12-17: padding with 0x20 (space)
    for i in range(12, 18):
        desc[i] = 0x20
    return desc


def make_name_descriptor(name):
    """Create a Monitor Name descriptor (18 bytes)."""
    desc = bytearray(18)
    desc[0] = 0x00
    desc[1] = 0x00
    desc[2] = 0x00
    desc[3] = 0xFC  # Monitor Name tag
    desc[4] = 0x00
    # Name: max 13 chars, terminated with 0x0A, padded with 0x20
    name_bytes = name[:13].encode('ascii')
    for i, b in enumerate(name_bytes):
        desc[5 + i] = b
    if len(name_bytes) < 13:
        desc[5 + len(name_bytes)] = 0x0A  # Line feed terminator
        for i in range(5 + len(name_bytes) + 1, 18):
            desc[i] = 0x20  # Space padding
    return desc


def make_serial_descriptor(serial):
    """Create a Monitor Serial Number descriptor (18 bytes)."""
    desc = bytearray(18)
    desc[0] = 0x00
    desc[1] = 0x00
    desc[2] = 0x00
    desc[3] = 0xFF  # Serial Number tag
    desc[4] = 0x00
    serial_bytes = serial[:13].encode('ascii')
    for i, b in enumerate(serial_bytes):
        desc[5 + i] = b
    if len(serial_bytes) < 13:
        desc[5 + len(serial_bytes)] = 0x0A
        for i in range(5 + len(serial_bytes) + 1, 18):
            desc[i] = 0x20
    return desc


def generate_edid(refresh_rate, width=1920, height=1080):
    """Generate a complete 128-byte EDID block."""
    edid = bytearray(128)

    # === Header (bytes 0-7) ===
    edid[0:8] = b'\x00\xFF\xFF\xFF\xFF\xFF\xFF\x00'

    # === Vendor & Product (bytes 8-17) ===
    # Manufacturer ID: "BWD" (Beagle Wind Display)
    # Encoded as: (B-64)<<10 | (W-64)<<5 | (D-64) = 2<<10 | 23<<5 | 4 = 2788 = 0x0AE4
    # Big-endian
    mfg_id = ((ord('B') - 64) << 10) | ((ord('W') - 64) << 5) | (ord('D') - 64)
    edid[8] = (mfg_id >> 8) & 0xFF
    edid[9] = mfg_id & 0xFF

    # Product code (little-endian): 0x0001
    edid[10] = 0x01
    edid[11] = 0x00

    # Serial number (4 bytes, little-endian)
    edid[12] = 0x01
    edid[13] = 0x00
    edid[14] = 0x00
    edid[15] = 0x00

    # Week of manufacture: 42
    edid[16] = 42
    # Year of manufacture: 2024 (year - 1990 = 34)
    edid[17] = 34

    # === EDID version 1.4 (bytes 18-19) ===
    edid[18] = 1  # Version
    edid[19] = 4  # Revision

    # === Basic Display Parameters (bytes 20-24) ===
    # Byte 20: Digital input, 8 bits per color, DisplayPort
    edid[20] = 0b10100101  # Digital, 8bpc, DP interface

    # Byte 21-22: Max H/V image size in cm (53x30 for ~24")
    edid[21] = 53  # H size cm
    edid[22] = 30  # V size cm

    # Byte 23: Gamma (2.2 = (2.2 - 1.0) * 100 = 120 = 0x78)
    edid[23] = 120

    # Byte 24: Feature support (DPMS standby/suspend/off, RGB color, preferred timing is native)
    edid[24] = 0b00101010  # DPMS off, RGB 4:4:4, preferred timing includes native pixel format

    # === Chromaticity (bytes 25-34) ===
    # Standard sRGB chromaticity coordinates
    edid[25] = 0xEE  # R/G low bits
    edid[26] = 0x95  # B/W low bits
    edid[27] = 0xA3  # Rx high
    edid[28] = 0x54  # Ry high
    edid[29] = 0x4C  # Gx high
    edid[30] = 0x99  # Gy high
    edid[31] = 0x26  # Bx high
    edid[32] = 0x0F  # By high
    edid[33] = 0x50  # Wx high
    edid[34] = 0x54  # Wy high

    # === Established Timings (bytes 35-37) ===
    edid[35] = 0x21  # 720x400@70, 640x480@60
    edid[36] = 0x08  # 1024x768@60
    edid[37] = 0x00

    # === Standard Timings (bytes 38-53) ===
    # Each is 2 bytes: (h_pixels/8 - 31), aspect_ratio<<6 | (refresh - 60)
    std_timings = [
        (1920, 1080, 60),   # Primary
        (1920, 1080, 120),  # High refresh
        (1920, 1080, 144),  # Max refresh
        (1280, 720, 60),    # 720p
        (1600, 900, 60),    # 900p
    ]

    idx = 38
    for h, v, r in std_timings:
        h_val = (h // 8) - 31
        # Aspect ratio: 16:9 = 0b11, 16:10 = 0b01, 4:3 = 0b00, 5:4 = 0b10
        aspect = 0b11 if (h * 9 == v * 16) else (0b01 if (h * 10 == v * 16) else 0b00)
        r_val = r - 60
        edid[idx] = h_val & 0xFF
        edid[idx + 1] = (aspect << 6) | (r_val & 0x3F)
        idx += 2

    # Fill remaining standard timings with 0x01, 0x01 (unused)
    while idx < 54:
        edid[idx] = 0x01
        edid[idx + 1] = 0x01
        idx += 2

    # === Detailed Timing Descriptors (bytes 54-125) ===
    # 4 descriptors, 18 bytes each

    # Descriptor 1 (bytes 54-71): Preferred Detailed Timing at target refresh
    timing = cvt_rb2_timing(width, height, refresh_rate)
    dtd = encode_dtd(timing)
    edid[54:72] = dtd

    # Descriptor 2 (bytes 72-89): Monitor Range Limits
    # Min V: 24Hz, Max V: max(refresh_rate, 144)Hz
    # Min H: 30kHz, Max H: calculated from timing
    max_v = max(refresh_rate, 144)
    max_h = timing['pixel_clock_khz'] // timing['v_total'] + 10  # kHz with margin
    max_pclk_mhz = (timing['pixel_clock_khz'] // 1000) + 10  # MHz with margin
    # Round up to next 10
    max_pclk_mhz = ((max_pclk_mhz + 9) // 10) * 10
    range_desc = make_monitor_range_descriptor(24, max_v, 30, max_h, max_pclk_mhz)
    edid[72:90] = range_desc

    # Descriptor 3 (bytes 90-107): Monitor Name
    name_desc = make_name_descriptor("BWD Gaming")
    edid[90:108] = name_desc

    # Descriptor 4 (bytes 108-125): Serial Number
    serial_desc = make_serial_descriptor("BWD%03dHZ" % refresh_rate)
    edid[108:126] = serial_desc

    # === Extension count (byte 126) ===
    edid[126] = 0  # No extension blocks

    # === Checksum (byte 127) ===
    # Sum of all 128 bytes must equal 0 mod 256
    checksum = (256 - (sum(edid[:127]) % 256)) % 256
    edid[127] = checksum

    return bytes(edid)


def validate_edid(data):
    """Validate EDID checksum."""
    return sum(data) % 256 == 0


def main():
    refresh_rate = int(sys.argv[1]) if len(sys.argv) > 1 else 60
    output_path = sys.argv[2] if len(sys.argv) > 2 else "/etc/X11/edid.bin"

    if refresh_rate not in (30, 60, 120, 144):
        print("WARNING: Non-standard refresh rate %d Hz, proceeding anyway" % refresh_rate)

    edid = generate_edid(refresh_rate)

    if not validate_edid(edid):
        print("ERROR: Generated EDID has invalid checksum!")
        sys.exit(1)

    with open(output_path, 'wb') as f:
        f.write(edid)

    # Print summary
    timing = cvt_rb2_timing(1920, 1080, refresh_rate)
    print("Generated EDID: 1920x1080 @ %d Hz" % refresh_rate)
    print("  Pixel clock: %.2f MHz" % (timing['pixel_clock_khz'] / 1000.0))
    print("  H total: %d, V total: %d" % (timing['h_total'], timing['v_total']))
    print("  Output: %s" % output_path)
    print("  Checksum: 0x%02X (valid)" % edid[127])


if __name__ == "__main__":
    main()
