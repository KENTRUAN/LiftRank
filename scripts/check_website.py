#!/usr/bin/env python3
"""Check the deploy directory and URLs without installing dependencies."""
from html.parser import HTMLParser
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "website"


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.links = []
        self.errors = []
        self.references = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        element_id = attrs.get("id")
        if element_id:
            if element_id in self.ids:
                self.errors.append(f"Duplicate id: {element_id}")
            self.ids.add(element_id)
        for attribute in ("src", "href"):
            if attribute in attrs:
                self.links.append(attrs[attribute])
        for attribute in ("aria-controls", "aria-labelledby", "aria-describedby"):
            self.references.extend(attrs.get(attribute, "").split())
        if tag == "img" and "alt" not in attrs:
            self.errors.append(f"Image without alt text: {attrs.get('src')}")
        if tag == "meta" and attrs.get("property") == "og:image":
            image = urlsplit(attrs["content"]).path.removeprefix("/LiftRank/")
            self.links.append("./" + image)


def main():
    page = Page()
    page.feed((SITE / "index.html").read_text())
    errors = page.errors
    for url in page.links:
        parsed = urlsplit(url)
        if parsed.scheme or parsed.netloc:
            continue
        if parsed.path.startswith("/"):
            errors.append(f"Root-relative URL breaks project hosting: {url}")
            continue
        target = SITE / unquote(parsed.path) if parsed.path else SITE / "index.html"
        if not target.resolve().is_relative_to(SITE.resolve()) or not target.is_file():
            errors.append(f"Missing or out-of-site URL: {url}")
        if parsed.fragment and not parsed.path and parsed.fragment not in page.ids:
            errors.append(f"Missing anchor: {url}")
    for reference in page.references:
        if reference not in page.ids:
            errors.append(f"Missing ARIA target: {reference}")
    for tier in ("wood", "bronze", "silver", "gold", "platinum", "diamond", "champion", "titan", "olympian"):
        for family in ("mascot", "doubao"):
            if not (SITE / "assets" / f"{family}-{tier}.png").is_file():
                errors.append(f"Missing {family} rank asset: {tier}")
    for name in ("rack", "bench", "cardio", "platform", "lounge", "floor", "wall"):
        if not (SITE / "assets" / f"gym-{name}.png").is_file():
            errors.append(f"Missing gym artwork: {name}")
    for name in ("accessory-crown.png", "backdrop-sunset.jpg"):
        if not (SITE / "assets" / name).is_file():
            errors.append(f"Missing cosmetic preview: {name}")
    allowed_extensions = {".html", ".css", ".js", ".png", ".jpg", ".svg", ".webp", ".ico"}
    size = 0
    for path in SITE.rglob("*"):
        if path.is_symlink():
            errors.append(f"Symlink in deployment: {path.relative_to(SITE)}")
        if not path.is_file():
            continue
        size += path.stat().st_size
        if path.suffix not in allowed_extensions and path.name != ".nojekyll":
            errors.append(f"Unexpected deployment file: {path.relative_to(SITE)}")
        if path.suffix in {".html", ".css", ".js", ".svg"}:
            text = path.read_text()
            if not text.endswith("\n"):
                errors.append(f"Missing final newline: {path.name}")
            if any(line.rstrip() != line for line in text.splitlines()):
                errors.append(f"Trailing whitespace: {path.name}")
            if re.search(r"^(<<<<<<< |=======$|>>>>>>> )", text, re.M):
                errors.append(f"Conflict marker: {path.name}")
    if size > 5_000_000:
        errors.append(f"Site exceeds 5 MB asset budget: {size:,} bytes")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Website checks passed: local URLs, anchors, ARIA targets, assets, deployment files ({size:,} bytes).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
