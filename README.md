# Azure Content Understanding PDF toolkit

Two small Python scripts for running a folder of PDFs through [Azure AI Content Understanding](https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/) and sanity-checking the results:

| Script | Purpose |
| --- | --- |
| `batch_content_understanding.py` | Submit every PDF in a folder to Content Understanding, save each result as JSON. |
| `compare_cu_to_pdf.py` | Compare those JSON outputs back against the original PDFs and flag any page whose text appears to be missing from the JSON. |

Typical workflow:

```
  my_pdfs/ ──► batch_content_understanding.py ──► cu_outputs/*.json
                                                         │
  my_pdfs/ ─────────────────────────────────────────► compare_cu_to_pdf.py ──► misses.csv
```

## Prerequisites

- Python 3.9+
- A Microsoft Foundry (Azure AI) resource with Content Understanding enabled, plus a default model deployment configured for that resource.
- Endpoint and key from the Azure portal (*your resource → Keys and Endpoint*).
- Dependencies:

  ```bash
  pip install requests pdfplumber
  ```

  `requests` is only needed for the batch script; `pdfplumber` is only needed for the comparison script.

## Setup

Set the endpoint and key as environment variables (recommended) or pass them via CLI flags.

**macOS / Linux:**

```bash
export CONTENTUNDERSTANDING_ENDPOINT="https://<your-resource>.cognitiveservices.azure.com"
export CONTENTUNDERSTANDING_KEY="<your-key>"
```

**Windows PowerShell:**

```powershell
$env:CONTENTUNDERSTANDING_ENDPOINT = "https://<your-resource>.cognitiveservices.azure.com"
$env:CONTENTUNDERSTANDING_KEY      = "<your-key>"
```

---

## 1. `batch_content_understanding.py`

Walks a folder for `*.pdf` files and, for each one:

1. POSTs the raw bytes to `{endpoint}/contentunderstanding/analyzers/{analyzerId}:analyzeBinary?api-version=2025-11-01` with the `Ocp-Apim-Subscription-Key` header.
2. Reads `Operation-Location` from the 202 response and polls every 2 seconds until the operation reaches `Succeeded` or `Failed` (10-minute ceiling per file).
3. Writes the full JSON result to `output_folder/<pdf-stem>.json`.

### Features

- Works with any analyzer ID — prebuilt (`prebuilt-documentAnalyzer`, `prebuilt-invoice`, `prebuilt-receipt`, ...) or custom.
- Parallel processing via a thread pool (default 4 workers).
- Idempotent: skips PDFs whose output JSON already exists unless `--overwrite` is set.
- Optional recursion into subfolders.
- Per-file polling timeout so a stuck operation can never block the run forever.
- No SDK dependency — only `requests`.

### Usage

```bash
# Default document analyzer
python batch_content_understanding.py ./my_pdfs ./cu_outputs

# Custom analyzer, recursive search, 8 workers
python batch_content_understanding.py ./my_pdfs ./cu_outputs \
    --analyzer-id my-custom-analyzer \
    --recursive \
    --workers 8

# Reprocess everything, ignoring existing JSON outputs
python batch_content_understanding.py ./my_pdfs ./cu_outputs --overwrite

# Pass endpoint and key inline instead of via env vars
python batch_content_understanding.py ./my_pdfs ./cu_outputs \
    --endpoint https://myresource.cognitiveservices.azure.com \
    --key 00000000000000000000000000000000
```

### CLI options

| Flag | Default | Purpose |
| --- | --- | --- |
| `input_folder` | (required) | Folder containing PDF files. |
| `output_folder` | (required) | Folder to write JSON outputs into. Created if missing. |
| `--analyzer-id` | `prebuilt-documentAnalyzer` | Analyzer to invoke. |
| `--api-version` | `2025-11-01` | Content Understanding REST API version. |
| `--endpoint` | `$CONTENTUNDERSTANDING_ENDPOINT` | Resource endpoint. |
| `--key` | `$CONTENTUNDERSTANDING_KEY` | Resource access key. |
| `--recursive` | off | Walk subfolders for PDFs. |
| `--overwrite` | off | Reprocess files even if `<stem>.json` already exists. |
| `--workers` | `4` | Number of PDFs processed concurrently. |

### Output

Each input `report.pdf` produces `output_folder/report.json` containing the raw service response, e.g.:

```json
{
  "id": "3b31320d-8bab-4f88-b19c-2322a7f11034",
  "status": "Succeeded",
  "result": {
    "analyzerId": "prebuilt-documentAnalyzer",
    "apiVersion": "2025-11-01",
    "createdAt": "2026-04-21T00:00:00Z",
    "contents": [ ... ],
    "warnings": []
  }
}
```

The shape of `result.contents` and `result.fields` depends on which analyzer you used.

### Configuration constants

Tunable constants near the top of `batch_content_understanding.py`:

| Constant | Default | Description |
| --- | --- | --- |
| `DEFAULT_ANALYZER_ID` | `prebuilt-documentAnalyzer` | Used when `--analyzer-id` is omitted. |
| `DEFAULT_API_VERSION` | `2025-11-01` | GA Content Understanding API version. |
| `POLL_INTERVAL_SECONDS` | `2.0` | Delay between status polls. |
| `POLL_TIMEOUT_SECONDS` | `600.0` | Per-file polling ceiling (seconds). |
| `REQUEST_TIMEOUT_SECONDS` | `60.0` | Per-HTTP-request socket timeout. |

Increase `POLL_TIMEOUT_SECONDS` if you regularly process very large or complex PDFs.

### Run summary

```
Processing 12 PDF(s) with analyzer 'prebuilt-documentAnalyzer' using 4 worker(s)...
  [ok] invoice_001.pdf -> invoice_001.json
  [skipped (exists)] invoice_002.pdf -> invoice_002.json
  [error: Submit failed (broken.pdf): HTTP 415 -- ...] broken.pdf -> broken.json
  ...
Done. ok=10, skipped=1, failed=1
```

Exit code is `0` when all files succeeded or were skipped, `1` when at least one failed, and `2` for configuration errors.

---

## 2. `compare_cu_to_pdf.py`

Compares each JSON output against its source PDF and prints any page whose words appear in the PDF but not in the JSON.

### How it works

1. **PDF side** — `pdfplumber` extracts text per page. Each page becomes a bag of normalised words (lowercased, punctuation stripped, tokens shorter than `--min-word-length` dropped).
2. **CU JSON side** — the script walks the JSON looking for `pageNumber` nodes and pulls each page's `words[].content` (or `lines[].content` if no words array). If the payload has no per-page structure it falls back to collecting every text-bearing field (`markdown`, `content`, `valueString`, `text`) across the whole document.
3. **Comparison** — for each PDF page it builds a `Counter` of words and compares against the matching CU page Counter (per-page mode) or the whole-document Counter (whole-doc mode). A word counts as missed when its PDF-page count exceeds its CU count.
4. **Output** — prints a line per flagged page and optionally writes a CSV or JSON report.

### Usage

```bash
# Basic run (matches PDFs to JSON files by filename stem)
python compare_cu_to_pdf.py ./my_pdfs ./cu_outputs

# Write a CSV report of every page with missing words
python compare_cu_to_pdf.py ./my_pdfs ./cu_outputs --report misses.csv

# Recurse into subfolders, ignore 1-letter tokens, show more words per page
python compare_cu_to_pdf.py ./my_pdfs ./cu_outputs \
    --recursive \
    --min-word-length 3 \
    --max-words-shown 30 \
    --report misses.json
```

### CLI options

| Flag | Default | Purpose |
| --- | --- | --- |
| `pdf_folder` | (required) | Folder containing the original PDFs. |
| `json_folder` | (required) | Folder containing the CU JSON outputs. |
| `--report` | off | Write a `.csv` or `.json` report (format picked from the extension). |
| `--min-word-length` | `2` | Ignore tokens shorter than this on both sides. |
| `--max-words-shown` | `15` | How many missing words to print per page. |
| `--recursive` | off | Walk subfolders when discovering PDFs. |

### Output

Per-page lines look like:

```
[ok]   invoice_001.pdf: no missing words detected (3 page(s))
[miss] report_q3.pdf p.2 (per-page): 4 word(s) -- addendum, exhibit, footnote, signatory
[miss] scan.pdf p.1 (whole-doc): 12 word(s) -- ... (+2 more)
Done. clean=8, flagged=4, total_pairs=12
```

CSV report columns:

| Column | Meaning |
| --- | --- |
| `pdf_name` | Source PDF filename. |
| `page` | 1-indexed PDF page number. |
| `mode` | `per-page` when CU gave page-level tokens, `whole-doc` when it didn't. |
| `missing_count` | How many PDF words didn't appear (or didn't appear often enough) in the CU output. |
| `missing_words` | Space-separated list of the missing words. |

Exit code is `0` when nothing is flagged, `1` when at least one PDF has missing words, and `2` for setup errors.

### Caveats worth knowing

- **OCR variance is real.** `Smith,` in the PDF vs `Smlth` from OCR will register as a miss even though the analyzer "saw" it. Treat the output as a triage list, not a verdict.
- **Whole-doc fallback is conservative.** If the CU payload has no per-page detail, the script can only verify whether a word exists *somewhere* in the JSON, not on the correct page. A word that appears `N` times in the PDF and `N` times anywhere in the JSON will pass even if every CU instance came from the wrong page. Per-page mode (which the prebuilt document analyzer provides) avoids this.
- **Tables, formulas, handwriting, and images-of-text** are common miss sources — pages flagged for those are usually genuine.
- **Stem matching** — each `foo.pdf` is matched to `foo.json` in the JSON folder. PDFs with no matching JSON print a `WARN` line and are skipped.

---

## Troubleshooting

- **`401 Unauthorized`** — wrong key for this endpoint. Double-check both values in the Azure portal.
- **`404 Not Found` on submit** — analyzer ID doesn't exist on the resource, or the API version isn't supported in your region.
- **`415 Unsupported Media Type`** — the file isn't being sent as `application/pdf`. The script sets this header automatically; the usual cause is a non-PDF file with a `.pdf` extension.
- **`429 Too Many Requests`** — lower `--workers` or add a delay between submissions. Content Understanding enforces per-resource rate limits.
- **Polling timeout** — the operation took longer than `POLL_TIMEOUT_SECONDS`. Raise the constant for very large documents.
- **Need OAuth instead of an API key** — swap the `Ocp-Apim-Subscription-Key` header for `Authorization: Bearer <token>` from `azure-identity`'s `DefaultAzureCredential` (scope `https://cognitiveservices.azure.com/.default`).
- **`pdfplumber` fails on a specific PDF** — the PDF is likely image-only or corrupt. Re-run after OCR'ing it, or exclude it from the comparison.

## When to prefer the official SDK

These scripts use raw REST calls to keep the dependency footprint tiny. For production workloads consider the official `azure-ai-contentunderstanding` Python SDK, which adds strongly-typed models, built-in long-running operation polling, `azure-identity` integration for managed identities and service principals, and automatic retries with exponential backoff.

## License

Use freely. No warranty.
