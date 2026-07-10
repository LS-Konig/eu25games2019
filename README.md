[![DOI](https://zenodo.org/badge/1208689018.svg)](https://doi.org/10.5281/zenodo.21294634)

# eu25games2019

Data-cleaning pipeline for a **3-wave EU elections survey (2019)** fielded across **25 countries**.
It turns the raw per-country Dynata exports into one tidy analysis dataset — one row per respondent × wave, carrying both the original responses and harmonized coded variables.

## Publications

This repo contains the full harmonized dataset underlying (with different processing procedures) the following publications:

- Hahm, Hyeonho, David Hilpert, and Thomas König. 2024. "Divided We Unite: The Nature of Partyism and the Role of Coalition Partnership in Europe." *American Political Science Review* 118(1): 69–87. [https://doi.org/10.1017/S0003055423000266](https://doi.org/10.1017/S0003055423000266)
- Hahm, Hyeonho, David Hilpert, and Thomas König. 2023. "Divided by Europe: Affective Polarisation in the Context of European Elections." *West European Politics* 46(4): 705–731. [https://doi.org/10.1080/01402382.2022.2133277](https://doi.org/10.1080/01402382.2022.2133277)

## The dataset

The final product is `data/03_final/eu25games2019.rds` (~103,685 rows × 833 columns):

- `q_*` — coded survey variables; `q_*_raw` — the original response strings (never dropped).
- `cj_*` — conjoint experiment attributes and outcomes (Waves 2–3 only).
- `prime_*` — priming-experiment paradata; `meta_*` — respondent/wave metadata.
- `ext_*` — externally merged [Party Facts](https://partyfacts.herokuapp.com/) party IDs/names.
- `der_*` — derived variables.

The file is **xz-compressed**, so it is far smaller on disk than its >1 GB uncompressed size. `read_rds()` / `readRDS()` decompress it transparently — no extra step needed.

The variables are documented in a **codebook** produced by `code/08_codebook.qmd`. Two ways to read it:

- **View online:** the [rendered codebook](http://htmlpreview.github.io/?https://github.com/LS-Konig/eu25games2019/blob/main/code/08_codebook.html), served through htmlpreview.github.io (GitHub does not render HTML files in-browser). The codebook is large (~11 MB), so this viewer can take a while to load.
- **Download and open locally** (more reliable): grab `code/08_codebook.html` — from your local clone, or on GitHub via the file's **Download raw file** button (⤓) — and open the downloaded file in any web browser. Viewing it directly on GitHub only shows the raw source; it must be downloaded to render.

### Loading it

```r
library(readr)
df <- read_rds("data/03_final/eu25games2019.rds")
# or base R:
df <- readRDS("data/03_final/eu25games2019.rds")
```

Remember to adjust the loading paths accordingly after downloading the dataset.

Companion files in `data/03_final/`:

- `variable_crosswalk.csv` — one row per (variable × wave): semantic name, original Dynata code, and English question wording.
- `ordinal_recode_check.csv` — audit trail for the multilingual ordinal recodes.

## Repository structure

```
eu25games2019/
├── README.md
├── code/                         # cleaning pipeline (Quarto notebooks, run in order)
│   ├── 01_explore.qmd            # question-wording lookup
│   ├── 02_compile.qmd            # bind 25 country frames into one per wave
│   ├── 03_clean_w1.qmd           # coalesce + rename Wave 1
│   ├── 04_clean_w2.qmd           # coalesce + rename Wave 2
│   ├── 05_clean_w3.qmd           # coalesce + rename Wave 3
│   ├── 06_stack.qmd              # stack all three waves
│   ├── 07_recode.qmd             # add coded columns, save final dataset
│   └── 08_codebook.qmd           # codebook generation
└── data/
    ├── 01_raw/                   # authoritative inputs
    │   ├── Wave1.rds             # list of 25 country dataframes
    │   ├── Wave2.rds
    │   └── Wave3.rds
    ├── 02_processed/             # intermediate caches (one per notebook)
    ├── 03_final/                 # deliverables
    │   ├── eu25games2019.rds     # full wide dataset (raw + coded + ext_)
    │   ├── variable_crosswalk.csv
    │   └── ordinal_recode_check.csv
    └── questionaire/             # reference questionnaires (Irish version of all 3 waves)
```

## Pipeline

The notebooks in `code/` run in order, each caching its output to `data/02_processed/` for the next:

| Notebook | Purpose |
|----------|---------|
| `01_explore` | Build the question-wording lookup |
| `02_compile` | Bind the 25 per-country frames into one dataframe per wave |
| `03_clean_w1` / `04_clean_w2` / `05_clean_w3` | Coalesce duplicate columns, rename to the semantic scheme |
| `06_stack` | Stack all three waves |
| `07_recode` | Add coded columns alongside raw, then save the final dataset + crosswalk |
| `08_codebook` | Generate the codebook |

Authoritative inputs: `data/01_raw/Wave{1,2,3}.rds` (each an R list of 25 country dataframes).
Run with R 4.5.3. Re-run `07_recode` end-to-end after any new recode to regenerate the deliverables.
