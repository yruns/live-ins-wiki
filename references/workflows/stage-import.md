# Stage And Import

## When to read

Read this when adding a Lark doc/wiki source, uploading a local file, dealing
with extraction metadata, or explaining why Stage is not Compile. This preserves
Karpathy's raw-source layer before any semantic rewrite happens.

## Workflow

1. Resolve the target Wiki root using `references/workflows/init-bootstrap.md`.
   For writes, confirm the target if the user did not specify root/name/`@current`
   in this turn.
2. Decide source category: `raw/docs`, `raw/articles`, `raw/repos`,
   `raw/meetings`, `raw/assets`, `raw/extracts`, or `raw/manifests`.
3. Stage means:
   - source is represented under `raw/`;
   - `SOURCES` has or updates one row;
   - `INDEX` Sources row and `LOG` import event are updated;
   - no claim is treated as compiled knowledge yet.
4. Preserve identity. If the same Lark origin/raw node/token or same local-file
   checksum already exists, reuse the existing `source_id` and update
   `updated_at`. Do not create duplicate source rows.
5. `SOURCES.imported_at` is immutable. Later stage/extract/compile/audit/drift
   changes only update `updated_at` and status fields.
6. Use second-precision timezone timestamps such as
   `YYYY-MM-DDTHH:MM:SS+08:00`.

## Lark doc/wiki source

1. Resolve source URL. `/wiki/` tokens must be resolved before use; normal
   `docx/doc` URLs are treated as source documents.
2. Create a shortcut under the chosen `raw/<category>`; do not move the original
   document unless the user explicitly asks.
3. Run:

   ```bash
   scripts/lark_wiki.sh wiki-stage-lark-doc "$ROOT" "$SOURCE_DOC_OR_WIKI_URL" docs
   ```

4. Ensure output says `Status: staged only. Not compiled.`
5. Continue to `references/workflows/compile.md` when the user wants ingest or
   semantic maintenance.

## Local file source

1. Upload the original file first. If upload fails, do not continue.
2. Create a raw file shortcut under `raw/assets` or the requested category.
3. Extract text with `scripts/extract_local_file.py`; store the extraction page
   under `raw/extracts`.
4. Default metadata must include filename, file hash, extracted-text hash,
   extraction completeness, missing modalities, extractor name, and timestamp.
5. Do not write a local absolute path into Wiki pages or `SOURCES` by default.
   Only write a redacted debug path when explicitly requested.
6. Use Lark raw file token, raw shortcut, extraction page, and checksum as
   provenance. A local path is not provenance.

## Extraction gaps

Local extraction is often partial. The extraction page should tell the compiler
what was not captured:

- `text_only`: plain text was extracted, but images/charts/comments may be lost.
- `text_plus_tables`: table values are present, but charts/formulas/comments may
  need human or multimodal review.
- `multimodal_partial`: image or page artifacts exist, but the extraction is not
  complete.
- `OCR_needed`: scanned pages have no reliable text and must not be silently
  treated as empty evidence.

## Karpathy alignment

Stage is the "drop source into raw" step. It deliberately avoids claiming the
Wiki learned anything yet. The compounding value appears only after the LLM
reads the source and writes durable `wiki/` pages.
