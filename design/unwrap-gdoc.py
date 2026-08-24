#!/usr/bin/env python3
"""Extract real HTML that was pasted into a Google Doc and exported as .html.

The Docs export escapes the code as text inside <span> elements and turns
newlines into <br>. This reverses that.
"""
import html
import re
import sys

src = sys.argv[1] if len(sys.argv) > 1 else "bodymap.html"
dst = sys.argv[2] if len(sys.argv) > 2 else "bodymap.fixed.html"

raw = open(src, encoding="utf-8").read()

# Keep only the document body - drop the Docs <head>/<style> chrome.
m = re.search(r"<body[^>]*>(.*)</body>", raw, re.S)
body = m.group(1) if m else raw

# <br> and </p> were line breaks in the original source.
body = re.sub(r"<br\s*/?>", "\n", body, flags=re.I)
body = re.sub(r"</p\s*>", "\n", body, flags=re.I)

# Drop every remaining tag - the real code is the text content.
text = re.sub(r"<[^>]+>", "", body)

# Undo entity escaping (&lt; &gt; &quot; &#39; &amp; &nbsp;).
text = html.unescape(text).replace("\xa0", " ")

if "<svg" not in text.lower():
    sys.exit("no <svg> found after unwrapping - is this really a Docs export?")

open(dst, "w", encoding="utf-8").write(text.strip() + "\n")
print(f"wrote {dst} ({len(text)} bytes)")
