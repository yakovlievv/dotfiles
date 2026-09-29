#!/usr/bin/env python3
"""Time-of-day glyph that sits in front of the clock.

  05-08 dawn   sunrise
  08-17 day    sun
  17-20 dusk   sunset
  20-05 night  moon
"""
import json
import time

PHASES = [  # (start hour, class, glyph) -- Weather Icons set, clearer than md at bar size
    (5, "dawn", "\uE34C"),    # wi-sunrise
    (8, "day", "\uE30D"),     # wi-day_sunny
    (17, "dusk", "\uE34D"),   # wi-sunset
    (20, "night", "\uE32B"),  # wi-night_clear
]

hour = time.localtime().tm_hour
cls, glyph = "night", PHASES[-1][2]
for start, name, g in PHASES:
    if hour >= start:
        cls, glyph = name, g

# trailing space: wi glyphs are wider than a mono cell and GTK clips the overflow
print(json.dumps({"text": glyph + " ", "class": cls, "tooltip": cls}))
