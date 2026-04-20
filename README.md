# Doc-Intel
# batch_content_understanding

Batch-process a folder of PDF files through [Azure AI Content Understanding](https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/) and save each result as a JSON file in an output folder.

For every `.pdf` in the input folder, the script:

1. Submits the raw bytes to the `analyzeBinary` endpoint of a Content Understanding analyzer.
2. Polls the returned long-running operation until it reaches a terminal state.
3. Writes the full JSON payload to `output_folder/<pdf-stem>.json`.

## Features

- Works with any analyzer ID, prebuilt (`prebuilt-documentAnalyzer`, `prebuilt-invoice`, `prebuilt-receipt`, ...) or custom.
- Parallel processing via a thread pool (default 4 workers).
- Idempotent: skips PDFs whose output JSON already exists unless `--overwrite` is set.
- Optional recursion into subfolders.
- Per-file polling timeout so a stuck operation can never block the run forever.
- No SDK dependency — only `requests`.

## Prerequisites

- Python 3.9+
- A Microsoft Foundry (Azure AI) resource with Content Understanding enabled, plus a default model deployment configured for that resource.
- The resource **endpoint** and **key** (Azure portal → your resource → *Keys and Endpoint*).
- Pip-installed dependency:

  ```bash
  pip install requests
  ```

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

## Usage

Basic run with the default document analyzer:

```bash
python batch_content_understanding.py ./my_pdfs ./cu_outputs
```

With a custom analyzer, recursive search, and 8 parallel workers:

```bash
python batch_content_understanding.py ./my_pdfs ./cu_outputs \
    --analyzer-id my-custom-analyzer \
    --recursive \
    --workers 8
```

Reprocess everything, ignoring existing JSON outputs:

```bash
python batch_content_understanding.py ./my_pdfs ./cu_outputs --overwrite
```

Pass endpoint and key inline instead of via env vars:

```bash
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

## Output

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

## Configuration constants

The script exposes a few tunable constants near the top of `batch_content_understanding.py`:

| Constant | Default | Description |
| --- | --- | --- |
| `DEFAULT_ANALYZER_ID` | `prebuilt-documentAnalyzer` | Used when `--analyzer-id` is omitted. |
| `DEFAULT_API_VERSION` | `2025-11-01` | GA Content Understanding API version. |
| `POLL_INTERVAL_SECONDS` | `2.0` | Delay between status polls. |
| `POLL_TIMEOUT_SECONDS` | `600.0` | Per-file polling ceiling (seconds). |
| `REQUEST_TIMEOUT_SECONDS` | `60.0` | Per-HTTP-request socket timeout. |

Increase `POLL_TIMEOUT_SECONDS` if you regularly process very large or complex PDFs.

## Run summary

When the script finishes you'll see a per-file status line and a final summary:

```
Processing 12 PDF(s) with analyzer 'prebuilt-documentAnalyzer' using 4 worker(s)...
  [ok] invoice_001.pdf -> invoice_001.json
  [skipped (exists)] invoice_002.pdf -> invoice_002.json
  [error: Submit failed (broken.pdf): HTTP 415 -- ...] broken.pdf -> broken.json
  ...
Done. ok=10, skipped=1, failed=1
```

Exit code is `0` when all files succeeded or were skipped, `1` when at least one failed, and `2` for configuration errors (missing endpoint/key, missing input folder).

## Troubleshooting

- **`401 Unauthorized`** — the key is wrong or doesn't match the endpoint's resource. Double-check both values in the Azure portal.
- **`404 Not Found` on submit** — the analyzer ID doesn't exist on this resource, or the API version isn't supported in your region. Confirm the analyzer in the Foundry portal and check region availability for `2025-11-01`.
- **`415 Unsupported Media Type`** — the file isn't being sent as `application/pdf`. The script sets this header automatically; the most common cause is a non-PDF file with a `.pdf` extension.
- **`429 Too Many Requests`** — lower `--workers` or add a delay between submissions. Content Understanding enforces per-resource rate limits.
- **Polling timeout** — the operation took longer than `POLL_TIMEOUT_SECONDS`. Raise the constant for very large documents.
- **Need OAuth instead of an API key** — swap the `Ocp-Apim-Subscription-Key` header for `Authorization: Bearer <token>` from `azure-identity`'s `DefaultAzureCredential` (scope `https://cognitiveservices.azure.com/.default`).

## When to prefer the official SDK

This script uses raw REST calls so it has no dependency beyond `requests`. For production workloads consider the official `azure-ai-contentunderstanding` Python SDK, which adds:

- Strongly-typed request/response models.
- Built-in long-running operation polling.
- `azure-identity` integration for managed identities and service principals.
- Automatic retries with exponential backoff.

## License

Use freely. No warranty.
