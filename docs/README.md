# docs/

Outward-facing material. Everything here is written for someone outside the
team — a client, a prospective client, a partner — and is deliberately free of
infrastructure specifics, credentials and client-identifying detail.

Internal reference material lives in `.claude/docs/` instead, and is loaded by
the agent on demand. The two directories are not the same audience and should
not be merged.

| File | What it is |
|---|---|
| `spec-driven-delivery.html` | The engineering method: the twelve phases, the four tracks, how enforcement works, what "tested" is required to mean, and what the method costs. Standalone — carries its own stylesheet and a print stylesheet. |
| `spec-driven-delivery.pdf` | The same document, rendered for print and for sending as an attachment. 9 pages, searchable text. |

Also published as an artifact at
<https://claude.ai/code/artifact/2767725f-4d86-4219-8ca0-4d41720d6070>
(private until shared).

## Regenerating the PDF

The PDF is generated from the HTML, so edit the HTML and re-render — never the
other way round:

```bash
(python3 -m http.server 8799 --directory docs &) ; sleep 1
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=old --disable-gpu --no-sandbox --virtual-time-budget=12000 \
  --no-pdf-header-footer \
  --print-to-pdf="$PWD/docs/spec-driven-delivery.pdf" \
  "http://127.0.0.1:8799/spec-driven-delivery.html"
pkill -f "http.server 8799"
```

Two things that are easy to get wrong here, both found while writing this:

- **Serve it over HTTP, don't open the file directly.** A `file://` render can
  skip the webfonts and silently fall back to system faces.
- **`--no-pdf-header-footer`, and `--headless=old`.** Without the flag Chrome
  stamps a date and the page title onto every sheet; on the new headless the
  flag is spelled differently and the first render came out with the stamp.

The figures in the document are counted from the working system, not estimated.
If the pipeline changes, re-count before re-publishing — the footer states the
date they were taken.
