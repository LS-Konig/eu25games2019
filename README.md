[![DOI](https://zenodo.org/badge/1208689018.svg)](https://doi.org/10.5281/zenodo.21294634)

# eu25games2019

Data-cleaning pipeline for a **3-wave EU elections survey (2019)** fielded across **25 countries**.
It turns the raw per-country Dynata exports into one tidy analysis dataset — one row per respondent × wave, carrying both the original responses and harmonized coded variables.

## Contents

- [Publications](#publications)
- [The dataset](#the-dataset)
  - [Loading it](#loading-it)
- [Sample structure: panel and refreshment](#sample-structure-panel-and-refreshment)
- [Experiments and randomizations](#experiments-and-randomizations)
  - [Wave 1: party-manifesto conjoint](#wave-1-party-manifesto-conjoint)
  - [Waves 2–3: dictator and trust games](#waves-23-dictator-and-trust-games)
  - [Priming experiments](#priming-experiments)
- [Data quality: raw responses and duplicate IDs](#data-quality-raw-responses-and-duplicate-ids)
  - [What is left in](#what-is-left-in)
  - [Duplicate IDs](#duplicate-ids)
  - [Recommended cleaning rule](#recommended-cleaning-rule)
- [Repository structure](#repository-structure)
- [Pipeline](#pipeline)
- [How to cite](#how-to-cite)

## Publications

This repo contains the full harmonized dataset underlying (with different processing procedures) the following publications:

- Hahm, Hyeonho, David Hilpert, and Thomas König. 2024. "Divided We Unite: The Nature of Partyism and the Role of Coalition Partnership in Europe." *American Political Science Review* 118(1): 69–87. [https://doi.org/10.1017/S0003055423000266](https://doi.org/10.1017/S0003055423000266)
- Hahm, Hyeonho, David Hilpert, and Thomas König. 2023. "Divided by Europe: Affective Polarisation in the Context of European Elections." *West European Politics* 46(4): 705–731. [https://doi.org/10.1080/01402382.2022.2133277](https://doi.org/10.1080/01402382.2022.2133277)

## The dataset

The final product is `data/03_final/eu25games2019.rds` (103,685 rows × 847 columns):

- `q_*` — coded survey variables; `q_*_raw` — the original response strings (never dropped).
- `cj_*` — conjoint / game attributes and outcomes (see [Experiments](#experiments-and-randomizations)).
- `prime_*` — priming-experiment assignment and paradata; `meta_*` — respondent/wave metadata.
- `ext_*` — externally merged [Party Facts](https://partyfacts.herokuapp.com/) party IDs/names.
- `der_*` — derived variables (e.g. the attention checks `der_att_check_*`).

The file is **xz-compressed**, so it is far smaller on disk (~29 MB) than its >1 GB uncompressed size. `read_rds()` / `readRDS()` decompress it transparently — no extra step needed.

The variables are documented in a **codebook** produced by `code/08_codebook.qmd`. Two ways to read it:

- **View online:** the [rendered codebook](http://htmlpreview.github.io/?https://github.com/LS-Konig/eu25games2019/blob/main/code/08_codebook.html), served through htmlpreview.github.io (GitHub does not render HTML files in-browser). The codebook is large (~11 MB), so this viewer can take a while to load.
- **Download and open locally** (more reliable): grab `code/08_codebook.html` — from your local clone, or on GitHub via the file's **Download raw file** button (⤓) — and open the downloaded file in any web browser. Viewing it directly on GitHub only shows the raw source; it must be downloaded to render.

Companion files in `data/03_final/`:

- `variable_crosswalk.csv` — one row per (variable × wave): semantic name, original Dynata code, and English question wording.
- `ordinal_recode_check.csv` — audit trail for the multilingual ordinal recodes.

### Loading it

Straight from GitHub, without cloning the repo:

```r
library(readr)

url <- "https://raw.githubusercontent.com/LS-Konig/eu25games2019/main/data/03_final/eu25games2019.rds"
tmp <- tempfile(fileext = ".rds")
download.file(url, tmp, mode = "wb")  # "wb" matters on Windows
df <- read_rds(tmp)
```

The file must be downloaded first: `readRDS(url(...))` cannot decompress an xz-compressed file over a connection.
To avoid re-downloading on every run, save it once (e.g. to `data/eu25games2019.rds`) and wrap the download in `if (!file.exists(...))`.
For reproducible work, replace `main` in the URL with a release tag or commit hash, or use the archived [Zenodo version](https://doi.org/10.5281/zenodo.21294634).

From a local clone or download:

```r
library(readr)
df <- read_rds("data/03_final/eu25games2019.rds")
# or base R:
df <- readRDS("data/03_final/eu25games2019.rds")
```

## Sample structure: panel and refreshment

The three waves bracket the European Parliament election of 23–26 May 2019:

| Wave | Main fieldwork (`meta_startdate`) | Rows | Experiments |
|------|-----------------------------------|-----:|-------------|
| 1 | late Jan – late Feb 2019 (a few rows Dec 2018 – May 2019) | 44,857 | party conjoint, five priming experiments |
| 2 | 17–25 May 2019 (pre-election; stragglers to July) | 25,767 | dictator + trust games, "more EU" prime |
| 3 | 28 May – early Aug 2019 (post-election) | 33,061 | dictator + trust games, CJEU prime |

The survey is **partly a panel and partly a refreshment sample**.
Some respondents were re-interviewed in later waves; others enter for the first time in Wave 2 or Wave 3.
There is **no flag variable** for this — derive it from the panelist ID.

IDs:

- `meta_pid` — the Dynata **panelist** ID. This is the person key that links waves.
- `meta_responseid` — the Qualtrics response ID. Unique per row; use it as the row key.
- `meta_psid` — a per-survey session/invitation ID. **Not** a person ID; do not link waves on it.

`meta_pid` is not guaranteed to be unique across countries (a handful of IDs occur in more than one country), so link on `meta_country` + `meta_pid`.
61 rows have no `meta_pid` and cannot be linked.

Participation patterns (distinct `meta_country` × `meta_pid`):

| Waves taken | Panelists |
|-------------|----------:|
| 1 only | 32,809 |
| 2 only | 9,106 |
| 3 only | 18,252 |
| 1 + 2 | 3,777 |
| 1 + 3 | 1,602 |
| 2 + 3 | 6,450 |
| 1 + 2 + 3 | 6,239 |

So a majority of Wave 2 rows (~61%) and of Wave 3 rows (~56%) come from respondents first seen in that wave.
To derive the panel structure:

```r
library(dplyr)

panel <- df |>
  filter(!is.na(meta_pid)) |>
  distinct(meta_country, meta_pid, meta_wave) |>
  summarise(
    der_waves      = paste(sort(meta_wave), collapse = "+"),  # e.g. "1+3"
    der_first_wave = min(meta_wave),
    .by = c(meta_country, meta_pid)
  )

df <- df |>
  left_join(panel, by = c("meta_country", "meta_pid")) |>
  mutate(der_refresh = meta_wave == der_first_wave & meta_wave > 1)
```

Things to keep in mind:

- **Respondents ≠ respondent-waves.** About a quarter of the people who played the games did so in both Wave 2 and Wave 3. Report both counts, and cluster standard errors / add random intercepts at the person level (`meta_pid`), not the row.
- **Carrying covariates forward.** Some items were asked only in Wave 1. For panelists, they can be filled into later waves by joining on `meta_country` + `meta_pid` — fill missing cells only, never overwrite later answers, and note that this assumes stability over a few months.
- Run the duplicate handling below **before** deriving the panel structure if you want the patterns to reflect clean responses only.

## Experiments and randomizations

All experiments are embedded in the survey and randomized by Qualtrics.
The reference questionnaires are in `data/questionaire/`.
Note that the files' internal headers are offset by one: `W2_…txt` is titled "W1" and `W3_…txt` "W2" (the original fieldwork labels counted the two election waves only); the file names match this repo's wave numbering.

### Wave 1: party-manifesto conjoint

Respondents are asked to imagine voting in the upcoming European election and see **three tasks**, each comparing two fictitious parties (A/B, C/D, E/F).

- Each party profile shows positions on **7 issues** (European integration, market regulation, asylum/immigration, environment/energy, security/defence, agriculture, trade). Each issue has 4 levels drawn with equal probability, one of which is always "No position".
- The **issue order** is randomized per respondent (`cj_rand_issue_order_raw`); the drawn profiles are stored as comma-separated strings in `cj_rand_party_{a..f}_raw`.
- Outcomes: forced choice `cj_task{1,2,3}_choice` (`profile_1` / `profile_2`) and a 5-point evaluation of each party `cj_task1_eval_{a,b}`, `cj_task2_eval_{c,d}`, `cj_task3_eval_{e,f}`.
- Page timing: `cj_task*_{firstclick,lastclick,pagesubmit,clickcount}`.

### Waves 2–3: dictator and trust games

Each respondent plays **three dictator games and then three trust games**, always as Player 1 against a different, fictitious Player 2 each round — **six decisions per respondent-wave**.

- **Dictator** (`cj_dict{1,2,3}_*`): Player 1 receives 10 tokens and decides how many to give to Player 2.
- **Trust** (`cj_trust{1,2,3}_*`): the amount sent is tripled and Player 2 may return any part of it; only the send decision is recorded.
- Outcome: `cj_<game>_pl2` (tokens sent, 0–10); `cj_<game>_pl1` is the amount kept. Round timing in `cj_<game>_{firstclick,…}`, instruction-page timing in `cj_{dict,trust}_instr_*`.
- The questionnaire mentions no real-money payout for the tokens.

**Co-player profiles.** Every round draws a fresh Player 2 profile with seven attributes, randomized independently:

| Attribute | Column | Levels |
|-----------|--------|--------|
| Age | `cj_<game>_age` | 18, 30, 42, 53, 65 |
| Gender | `cj_<game>_sex` | male, female |
| Social class | `cj_<game>_class` | lower, middle, upper |
| Religion | `cj_<game>_rel` | catholic, protestant, muslim, non-religious |
| Nationality | `cj_<game>_nationality_drawn` / `_shown` | own_country, eu, non_eu |
| EU stance | `cj_<game>_eupos` | eu_citizen, not_eu_citizen ("feels (not) a citizen of the EU") |
| Party | `cj_<game>_party_raw`, `ext_cj_<game>_party_pf_{name,id}` | a national party of the respondent's country |

The **display order** of the attributes is randomized once per respondent and kept for all six rounds: `cj_attr_order` (e.g. `"class,nat,sex,eupos,party,age,rel"`) and the positions `cj_att_pos_<attr>` (1–7).

**Treatment conditions.** Each round is independently assigned one of four conditions (`cj_<game>_treatment`), which determine which attributes are actually *shown*:

| Condition | Share | Nationality shown | EU stance shown | Party shown |
|-----------|------:|-------------------|:---------------:|:-----------:|
| `1_conat_eustance_partisan` | 4/11 | own country | yes | yes |
| `2_conat_partisan` | 2/11 | own country | — | yes |
| `3_eunat_eustance` | 2/11 | other EU country | yes | — |
| `4_somenat` | 3/11 | the drawn value | — | — |

Age, gender, class and religion are shown in every condition.
Party is shown only for co-nationals, since a foreign co-player could not vote for a national party.

**Drawn is not shown.** The attribute columns hold the value *drawn* behind the scenes in every round, whether or not it was displayed:

- `cj_<game>_nationality_drawn` is a background lottery (~50% own country / 25% EU / 25% non-EU) that the treatment overrides in conditions 1–3. Use `cj_<game>_nationality_shown` for what the respondent actually saw.
- `cj_<game>_eupos` and the party columns carry a value in all conditions. Condition on `cj_<game>_treatment` (EU stance: conditions 1 and 3; party: conditions 1 and 2) before treating them as displayed.

**How the party was drawn.** The co-player's party was drawn with reference to the respondent's own party attachment: respondents who named a party meet a co-partisan in roughly half of party-shown rounds; others get parties drawn from their country's main parties.
Known glitches in `cj_<game>_party_raw`: in Latvia the draw copied respondents' own "no party" answers into the co-player's party (Party Facts name `none`), and a few rounds in Portugal and Romania have an empty party.

Because every round is randomized separately, a respondent typically experiences several conditions; analyse at the round level (reshape the six `cj_<game>_*` blocks to long) and cluster by respondent.

### Priming experiments

Survey vignettes randomize a short text before an outcome battery.
The assigned arm is in `prime_<exp>_condition`, the displayed text in `prime_<exp>_text`, and page timing in `prime_<exp>_{firstclick,lastclick,pagesubmit,clickcount}`.

| Wave | Experiment | Arms (`prime_<exp>_condition`) |
|------|------------|--------------------------------|
| 1 | `respresp` — government responsiveness vs. responsibility | responsiveness, responsibility, control_text, control_notext |
| 1 | `gridlock` — EU gridlock (refugee crisis) | gridlock, no_gridlock, control_text, control_notext |
| 1 | `court` — national high court rulings | majority, minority, control_text, control_notext |
| 1 | `compliance` — compliance with EU law (immigration) | 10 arms: nat_legislation, transpose, no_transpose_(no)sanction + consistency / economic / legality / reputation variants |
| 1 | `econblame` — economic blame | immigration_displayed, immigration_not_displayed |
| 2 | `moreeu` — "European integration has gone too far / should go further" | further_eu, too_far, too_far_econ, too_far_culture, too_far_political, control |
| 2 | `cjeu` — CJEU question | control_text only (no manipulation in Wave 2) |
| 2 (France) | `cjeu_fra` — CJEU | majority, minority, control_text, control_notext |
| 3 | `cjeu` — CJEU rulings | majority, minority, control_text, control_notext |

**France fork (Wave 2).** French Wave 2 respondents received an additional set of outcome batteries and the 4-arm CJEU experiment, stored in `_fra` variables (`q_*_fra`, `prime_cjeu_fra_*`).
These overlap with, rather than replace, the general items — analyse them separately and do not coalesce them blindly into the base columns.

## Data quality: raw responses and duplicate IDs

The dataset is **harmonized but not filtered**: every response in the original Dynata/Qualtrics exports is kept, including incomplete, failed and duplicated ones.
Recoding adds columns; it never removes rows.
Every analysis therefore needs its own sample definition.

### What is left in

| | Wave 1 | Wave 2 | Wave 3 |
|---|---:|---:|---:|
| Rows | 44,857 | 25,767 | 33,061 |
| Not finished (`meta_finished == FALSE`) | 4,957 | 3,409 | 4,747 |
| Flagged spam (`meta_status == "Spam"`) | 21 | 13 | 7 |
| Pass strict attention check (`der_att_check_3`) | 21,923 | 15,305 | 18,476 |
| `meta_pid` × wave with >1 row | 379 | 173 | 423 |
| Missing `meta_pid` | 40 | 17 | 4 |

**Attention check.** Respondents were told to select "Other" and type "I read the instructions".
`der_att_check_1` = selected "Other"; `der_att_check_2` = typed something in the text box (content not checked); `der_att_check_3` = both (recommended).
Pass rates are low (~50–60%), so the choice of check matters for sample size.

No speeder or straight-lining flags are provided; `meta_duration_s` (survey duration in seconds) and `meta_progress` are available if you want to build them.

### Duplicate IDs

The same `meta_pid` appears more than once **within a wave** for roughly 1,000 panelist-waves. The patterns:

- **Restarts (the vast majority).** A broken-off, unfinished attempt followed by a complete one. Keeping the finished row resolves these.
- **Multiple finished submissions (a few dozen).** Usually near-identical submissions minutes apart, most likely an invitation link that worked twice. After the attention-check filter, fewer than 20 IDs remain in this state.
- **Shared/test IDs.** One Estonian ID (`1575599903`) has dozens of rows across countries and waves whose demographics point to different people.

Since there is no principled way to choose between two complete submissions from the same ID, the conservative choice is to drop such panelists entirely — from **all** waves, since their cross-wave link is equally doubtful.

### Recommended cleaning rule

```r
library(dplyr)

key <- c("meta_wave", "meta_country", "meta_pid")

clean <- df |>
  filter(!is.na(meta_pid), der_att_check_3) |>
  add_count(across(all_of(key)), name = "n_rows") |>
  filter(n_rows == 1 | meta_finished) |>          # restarts: keep finished
  add_count(across(all_of(key)), name = "n_left")

unresolved <- clean |>
  filter(n_left > 1) |>
  distinct(meta_country, meta_pid)

clean <- clean |>
  anti_join(unresolved, by = c("meta_country", "meta_pid")) |>  # drop from all waves
  filter(meta_finished) |>
  select(-n_rows, -n_left)

stopifnot(!anyDuplicated(clean[key]))
```

This drops 17 panelists as unresolved and leaves 21,005 / 13,422 / 15,874 rows in Waves 1 / 2 / 3.
In Waves 2–3 this gives ~29,300 respondent-waves with game data from ~22,850 distinct panelists.

Adapt as needed:

- Apply the attention check after deduplication if you want duplicates resolved on the full sample.
- Instead of dropping unresolved IDs, you could keep the earliest submission (`meta_startdate`) or the most complete one (`meta_progress`, fewest missing items) — document whichever you choose.
- A stricter alternative (used in the original publications' preparation) drops every ID that is duplicated within a country at all.
- Optionally also drop `meta_status == "Spam"` and implausibly fast completions (`meta_duration_s`).

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
Run with R 4.6.1. Re-run `07_recode` end-to-end after any new recode to regenerate the deliverables.

## How to cite

If you use this dataset or pipeline, please cite it via its DOI (this resolves to the latest version):

> Muno, Tristan, and Thomas König. *eu25games2019: A cleaned three-wave EU elections survey (2019) across 25 countries*. Zenodo. https://doi.org/10.5281/zenodo.21294634

Please also cite the source study, whose survey design and data collection underlie this dataset:

> Hahm, Hyeonho, David Hilpert, and Thomas König. 2024. "Divided We Unite: The Nature of Partyism and the Role of Coalition Partnership in Europe." *American Political Science Review* 118(1): 69–87. https://doi.org/10.1017/S0003055423000266

Machine-readable citation metadata is in [`CITATION.cff`](CITATION.cff).
