# Claude Code Task Brief: Convert Three Model Inputs into the Shared Data Template

## Role and objective

Act as a careful data-integration engineer working inside the current
Git repository.

Your task is to inspect the repository, identify the shared input
template and its validation rules, and implement **R conversion scripts
for the three model input folders** under `inputs/`. Each converter
should read the available source files, extract and translate any
variables that can be mapped defensibly, and write data in the exact
shared template format.

The source files may include CSVs, Excel workbooks, manually copied
tables, inconsistent headers, notes, multiple sheets, merged cells,
units in labels, and other irregularities. Do not expect the data to be
clean or structurally consistent. The goal is not to map every possible
template variable. The goal is to produce a useful, evidence-based
subset of valid template entries and clearly document how each was
derived.

## 1. Start by inspecting the repository

Before changing anything:

1.  Inspect the current working directory and repository structure,
    including relevant subfolders and files.
2.  Check Git status and identify existing changes. **Do not overwrite,
    reset, discard, or reformat unrelated user work.**
3.  Identify the three model-specific folders inside `inputs/`. Record
    their exact names and inspect their contents recursively.
4.  Find and read the input template documentation and any related
    schema, examples, validation scripts, tests, or existing conversion
    scripts. Treat the repository's template documentation and
    validation code as the authority.
5.  Identify the expected output directory, naming conventions, required
    columns, allowed values, naming patterns, and validation command.
6.  Inspect file types and sizes before reading them. Avoid dumping huge
    files wholesale; inspect representative samples, sheet names,
    headers, dimensions, and relevant ranges first.

Create a short implementation plan based on what you find. Continue
autonomously unless a genuine blocker prevents reliable progress. Do not
ask questions that can be resolved by inspecting the repository.

## 2. Understand the shared template before mapping data

Read the template documentation carefully. Determine:

-   Exact required output columns, column order, and data types.
-   Which columns may be blank and which are mandatory.
-   The naming convention for template entries and any allowed codes,
    categories, units, regions, years, scenarios, or other dimensions.
-   Whether names such as `COST-WHEA-FUEL` are literal examples, follow
    a formal pattern, or are subject to a controlled vocabulary.
-   Whether the template expects long or wide data, and how individual
    observations/entries are represented.
-   The authoritative way to validate the final CSVs.

Do not infer template rules from an example alone if documentation or
validation code is available. If the documentation and validator
disagree, record the discrepancy and follow the most authoritative
project convention, explaining your choice.

## 3. Inspect and interpret the three source folders

Treat each model folder as an independent source that may require its
own conversion logic. Explore all relevant files, including Excel
workbooks with multiple sheets.

Source data may have been manually copied into Excel. Expect
irregularities such as:

-   Several header rows, blank rows/columns, merged cells, footnotes,
    comments, or explanatory text.
-   Different names for the same concept, spelling variations,
    abbreviations, or inconsistent capitalisation.
-   Values and units embedded in column or row labels.
-   Data spread across sheets, blocks, or tables.
-   Wide tables that need to be reshaped to a long format.
-   Regional, crop, year, scenario, or production-system distinctions
    that are not immediately obvious.
-   Formula cells, empty cells, subtotals, duplicate records, and notes
    mixed into data ranges.

Use robust, inspectable methods to identify meaningful data regions.
Preserve the source files unchanged. Do not assume that every sheet is
data, or that the first row is always the header.

For each source folder, maintain a concise inventory of files inspected,
potentially useful content, and limitations. Do not spend
disproportionate effort extracting information that cannot be mapped to
the template.

## 4. Mapping policy: evidence first, useful partial coverage

The number of possible template variables may be in the hundreds.
**Partial coverage is acceptable and expected.** Map every variable that
has defensible source evidence, even if only a small subset of the
template can be populated from a particular model.

For each candidate mapping:

1.  Identify the source file, worksheet/table, and source field or row
    label.
2.  Determine the concept represented, including units, commodity/crop,
    activity, geography, time period, scenario, and other dimensions
    where applicable.
3.  Match it to the template's naming rules and controlled vocabulary.
4.  Convert units only when the conversion is supported and unambiguous.
    Document the conversion and its basis.
5.  Preserve the meaning and granularity of the source. Do not
    manufacture dimensions or imply distinctions that the source does
    not contain.
6.  Record the mapping and its confidence in the mapping documentation.

For example, if a source clearly contains diesel fuel use or diesel fuel
cost per hectare for wheat, and the template's naming rules define
`COST-WHEA-FUEL` as the corresponding cost entry, map it to that entry
only if the concept and units genuinely match. Do not map fuel **use**
to fuel **cost** without a documented, justified calculation and the
required price information.

Use these evidence categories:

-   **Direct:** source label and definition clearly match the template
    concept.
-   **Normalised:** a clear match after spelling, abbreviation, naming,
    or unit normalisation.
-   **Derived:** calculated from source data using a transparent,
    justified formula.
-   **Ambiguous / candidate only:** potentially relevant, but
    insufficient evidence to populate the template safely.

Only Direct, Normalised, and sufficiently justified Derived mappings
should be included in the final converted data. Keep ambiguous
candidates in the mapping log with the reason they were not included. Do
not force matches just to increase coverage.

Never invent values, infer missing observations without explicit
authorisation, silently substitute zeros for missing values, or treat a
blank as zero. Do not use fuzzy string matching as the sole basis for a
mapping. Fuzzy matching may help identify candidates, but the semantic
match must be reviewed and documented.

## 5. Implement the converters in R

Use R for the conversion scripts. Follow existing repository conventions
and reuse existing project utilities where suitable.

Create a clear structure, adapting to repository conventions rather than
imposing an unnecessary new layout. Prefer one independently runnable
converter per model folder, with shared helper functions where useful.
For example, the project may end up with a structure similar to:

``` text
<repository>/
  inputs/
    <model_1>/
    <model_2>/
    <model_3>/
  scripts/                 # or the repository's existing scripts location
    <model_1>_to_template.R
    <model_2>_to_template.R
    <model_3>_to_template.R
    shared_conversion_helpers.R
  outputs/                 # or the expected output location
    <model_1>/
      <converted_file>.csv
      README.md
      mapping_log.csv
    <model_2>/
      <converted_file>.csv
      README.md
      mapping_log.csv
    <model_3>/
      <converted_file>.csv
      README.md
      mapping_log.csv
```

This is illustrative, not a required layout. First establish the
repository's existing conventions and the output location expected by
the template workflow.

### Implementation requirements

-   Use relative paths rooted in the repository or a robust project-root
    discovery method; do not hard-code a personal absolute path.
-   Make scripts runnable from a documented working directory and
    explain how to run them.
-   Read CSV and Excel files using suitable R packages already installed
    or already used by the repository where possible. For Excel, inspect
    sheet names and support selecting relevant sheets explicitly.
-   Handle character encoding, delimiters, decimal marks, missing
    values, and header irregularities deliberately.
-   Reshape data as needed, while preserving the meaning of dimensions
    and observations.
-   Keep source-specific parsing separate from common template
    formatting and validation logic.
-   Use explicit mapping tables or dictionaries rather than burying all
    mappings in opaque conditional logic.
-   Avoid modifying source files.
-   Avoid introducing dependencies unless needed. If a new package is
    necessary, document it and provide a clear installation note; do not
    install packages silently.
-   Make scripts safe to rerun. They should regenerate outputs
    deterministically, without appending duplicates or modifying
    unrelated files.
-   Emit useful messages about files read, sheets used, rows extracted,
    mappings applied, rows excluded, and validation failures.
-   Fail clearly on critical schema violations. Do not silently produce
    an apparently successful but invalid output.
-   Use functions and comments to make source-specific decisions
    understandable and maintainable.

## 6. Output schema and validation

The template documentation and repository validator determine the exact
schema. Every output CSV must follow the template exactly, including
column names, column order, permitted naming conventions, and required
fields.

Before writing outputs:

1.  Normalise values to the required template representation.
2.  Check that every output column is present and correctly named.
3.  Check template entry names against the documented naming rules and
    permitted values.
4.  Check data types, mandatory fields, and other documented
    constraints.
5.  Check for duplicate entries using the appropriate key defined by the
    template.
6.  Check for invalid or unexplained missing values.
7.  Check that no unsupported extra columns are emitted.

After writing outputs, run the repository's official template validation
process, if available. If it can validate only a combined file, follow
the documented workflow and validate the generated files in the intended
way. Do not create a substitute validator and claim that it is the
official one.

If no executable validator exists, implement reasonable local checks
based on the documentation and clearly state that the official validator
was unavailable. Do not claim full compliance where only partial checks
were possible.

Keep validation results separate from the data itself, such as in
console output or a validation report. Do not add helper columns to the
template CSV unless the schema explicitly allows them.

## 7. Documentation: a README for every model output

Create a concise `README.md` alongside each model's output. Each README
should allow another researcher to understand what was extracted and how
to reproduce it.

Include:

1.  **Source overview:** which source files and worksheets/tables were
    used.
2.  **Output overview:** output file path, number of rows, columns, and
    general scope.
3.  **Mappings:** a human-readable explanation of each included template
    entry or mapping group, linking the source concept to the final
    template entry.
4.  **Transformations:** any renaming, reshaping, aggregation, unit
    conversion, calculation, or filtering.
5.  **Limitations:** relevant missing dimensions, uncertain
    interpretations, excluded candidate variables, and source-data
    quality issues.
6.  **Validation:** checks run, results, and any unresolved warnings.
7.  **Reproduction:** R script to run, working-directory expectations,
    and package requirements.

Use concrete explanations. For example:

> `COST-WHEA-FUEL`: mapped from the source workbook's wheat diesel/fuel
> cost per hectare field. The source unit was \[unit\]; \[conversion, if
> any\] was applied. Source: `[file.xlsx]`, sheet `[sheet]`, field/row
> `[label]`.

Replace bracketed placeholders with verified information from the actual
files. If the source represents fuel use rather than fuel cost, say so
and do not claim it supports a cost entry unless a justified calculation
is possible.

## 8. Mapping log and traceability

In addition to each README, create a machine-readable mapping log for
each model, preferably CSV, unless the repository already uses a better
documented format.

Include columns where applicable such as:

-   `source_file`
-   `source_sheet`
-   `source_table_or_range`
-   `source_variable`
-   `source_label_or_definition`
-   `source_unit`
-   `template_entry`
-   `template_column_or_field`
-   `transformation`
-   `output_unit`
-   `mapping_status` (Direct, Normalised, Derived, or excluded
    candidate)
-   `confidence`
-   `notes`
-   `exclusion_reason`

Use actual source locations and labels whenever possible. If exact
cell/range tracing is impractical, provide the best reproducible
location, such as worksheet and column/row label. The mapping log should
make it possible to trace a converted entry back to its origin and
understand the translation.

Document excluded ambiguous candidates too, where useful, without
putting them into the validated template output. Do not record
unsupported claims about source locations or definitions.

## 9. Quality assurance and testing

Test each converter on the actual repository data. At minimum:

-   Run each script from the documented location.
-   Confirm that it reads the intended files and sheets.
-   Confirm that it produces the expected output files.
-   Run all available template/schema validation.
-   Check row counts and mapping counts for plausibility.
-   Inspect representative output rows manually against their source.
-   Check for accidental duplication, incorrect joins, dropped
    dimensions, unit mismatches, and character/encoding problems.
-   Confirm that rerunning the script produces the same result and does
    not duplicate data.
-   Check that outputs do not contain example values, placeholders,
    debug rows, or invented data.

If the repository has tests, extend or use them where appropriate. Add
small tests for shared helper functions and critical transformations if
practical. Report tests that could not be run and why.

## 10. Git and change management

-   Do not delete or overwrite source files.
-   Do not change unrelated project files.
-   Do not commit changes unless explicitly asked.
-   Do not modify the template definition merely to make converted data
    pass.
-   Do not suppress validation errors or loosen naming rules to obtain a
    successful run.
-   Keep generated outputs limited to the expected location and follow
    `.gitignore` and repository conventions.
-   Before finishing, inspect `git diff` and `git status` to identify
    exactly what changed.

## 11. Final report

When finished, provide a concise summary covering:

-   The three model folders found and the files/sheets that yielded
    usable data.
-   Scripts created and how to run each one.
-   Output CSVs and accompanying READMEs/mapping logs.
-   Number of template entries and output rows produced for each model.
-   Validation results and any unresolved errors or warnings.
-   Important assumptions, unit conversions, ambiguous mappings
    excluded, and source limitations.
-   Any work left incomplete and the specific reason.

Be honest about coverage. A small number of well-supported, validated
mappings is better than a large number of speculative ones. If one
model's source files do not contain a defensible match for a template
variable, leave that variable unmapped and explain why.

## Definition of done

The task is complete when:

-   The repository and template rules have been inspected.
-   A converter exists for each of the three model input folders.
-   Each converter runs reproducibly in R and writes schema-compliant
    output, to the extent supported by the data and validation tools.
-   Every included mapping is documented and traceable.
-   Each model output has its own README and mapping log.
-   Validation has been run and results are reported accurately.
-   Git changes have been reviewed and unrelated work remains untouched.
