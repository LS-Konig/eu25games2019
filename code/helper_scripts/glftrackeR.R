# R Script: Find files larger than a threshold and add them to Git LFS tracking.
# Optimised for large projects: uses a native OS file-scan instead of R-level
# file.info() to avoid per-file stat() syscall overhead.

# 1. Configuration ---------------------------------------------------------

target_dir <- "." # Directory to scan (default: working dir)
size_threshold_mb <- 100 # Threshold in MB (easier to read/change)
dry_run <- FALSE # TRUE = report only, do not write anything
lfs_suffix <- " filter=lfs diff=lfs merge=lfs -text"

# Derived — do not edit below this line
size_threshold_bytes <- size_threshold_mb * 1024 * 1024
target_dir <- normalizePath(target_dir, mustWork = TRUE)

# gitattributes_path is derived AFTER normalizePath so it uses the resolved dir
gitattributes_path <- file.path(target_dir, ".gitattributes")

# 2. Safety checks ---------------------------------------------------------

git_dir <- file.path(target_dir, ".git")
if (!dir.exists(git_dir)) {
  warning(
    "No .git directory found in: ",
    target_dir,
    "\n",
    "Make sure you are running this script from the root of a Git repository."
  )
}

# 3. Find large files (OS-native, fast) ------------------------------------

is_windows <- .Platform$OS.type == "windows"

find_large_files <- function(dir, min_bytes) {
  if (is_windows) {
    # system2() is the correct R function for subprocess calls.
    # shell(intern=TRUE) routes through cmd.exe in a way that can cause R to
    # exit silently when invoked via source() or RStudio's console on some
    # Windows/R version combinations.
    raw <- system2(
      "cmd.exe",
      args = c("/c", "dir", "/s", "/b", "/a-d", paste0('"', dir, '"')),
      stdout = TRUE,
      stderr = FALSE
    )
    raw <- raw[nchar(raw) > 0]

    # Batch file.info on the full list (one vectorised call — much faster than
    # calling it after list.files(), because we avoid the R-level loop).
    info <- file.info(raw)
    large_abs <- raw[!is.na(info$size) & info$size > min_bytes]
  } else {
    # system2() with a character args vector avoids shell quoting issues and
    # is safer than constructing a command string for system().
    large_abs <- system2(
      "find",
      args = c(
        shQuote(dir),
        "-not",
        "(",
        "-path",
        shQuote(paste0(dir, "/.git")),
        "-prune",
        ")",
        "-type",
        "f",
        "-size",
        paste0("+", min_bytes - 1, "c")
      ),
      stdout = TRUE,
      stderr = FALSE
    )
    large_abs <- large_abs[nchar(large_abs) > 0]
  }

  large_abs
}

cat(
  "🔍 Scanning",
  target_dir,
  "for files larger than",
  size_threshold_mb,
  "MB...\n"
)
large_abs <- find_large_files(target_dir, size_threshold_bytes)

# 4. Convert to relative, normalised paths ---------------------------------

to_relative <- function(abs_paths, base_dir) {
  # Normalise BOTH sides to forward slashes first, before any regex work.
  # This avoids escaping issues with Windows backslashes inside base_dir.
  base_fwd <- gsub("\\\\", "/", base_dir)
  paths_fwd <- gsub("\\\\", "/", abs_paths)

  # Escape regex metacharacters (dots, parens, etc.) then strip the prefix.
  base_escaped <- gsub("([.+*?^${}()|\\[\\]])", "\\\\\\1", base_fwd)
  rel <- sub(paste0("^", base_escaped, "/?"), "", paths_fwd)

  # Safety check: warn and drop anything that still looks absolute,
  # which would indicate the prefix strip silently failed.
  looks_absolute <- grepl("^([A-Za-z]:/|/)", rel)
  if (any(looks_absolute)) {
    warning(
      "Could not strip base directory from ",
      sum(looks_absolute),
      " path(s) — they will be skipped:\n",
      paste(rel[looks_absolute], collapse = "\n")
    )
    rel <- rel[!looks_absolute]
  }

  rel
}

large_rel <- to_relative(large_abs, target_dir)

# Exclude .gitattributes itself (shouldn't be large, but be safe)
large_rel <- large_rel[large_rel != ".gitattributes"]

# 5. Report & write --------------------------------------------------------

if (length(large_rel) == 0) {
  cat(
    "\n✅ No files larger than",
    size_threshold_mb,
    "MB found in:",
    target_dir,
    "\n"
  )
} else {
  cat("\n📦 Found", length(large_rel), "file(s) above threshold:\n")
  cat(paste0("   ", large_rel, collapse = "\n"), "\n\n")

  # Build LFS entries
  lfs_entries <- paste0(large_rel, lfs_suffix)

  # Read existing .gitattributes (if any), guard against missing trailing newline
  existing_lines <- character(0)
  if (file.exists(gitattributes_path)) {
    existing_lines <- readLines(gitattributes_path, warn = FALSE)
  }

  new_entries <- setdiff(lfs_entries, existing_lines)
  already_tracked <- intersect(lfs_entries, existing_lines)

  if (length(already_tracked) > 0) {
    cat("ℹ️  Already tracked (skipped):", length(already_tracked), "file(s)\n")
  }

  if (length(new_entries) == 0) {
    cat("✅ All large files are already tracked by LFS — nothing to do.\n")
  } else {
    cat("➕ New entries to add:", length(new_entries), "\n")
    cat(paste0("   ", new_entries, collapse = "\n"), "\n\n")

    if (dry_run) {
      cat("🔒 Dry-run mode: .gitattributes was NOT modified.\n")
      cat("   Set dry_run <- FALSE to apply changes.\n")
    } else {
      # Ensure the file ends with a newline before appending
      if (file.exists(gitattributes_path)) {
        raw_bytes <- readBin(
          gitattributes_path,
          "raw",
          file.info(gitattributes_path)$size
        )
        if (
          length(raw_bytes) > 0 && raw_bytes[length(raw_bytes)] != as.raw(0x0a)
        ) {
          cat("\n", file = gitattributes_path, append = TRUE)
        }
      }

      con <- file(gitattributes_path, open = "a")
      writeLines(new_entries, con = con, sep = "\n")
      close(con)

      cat(
        "✅ Added",
        length(new_entries),
        "new entry/entries to .gitattributes\n\n"
      )
      cat("Next steps:\n")
      cat("  git lfs install           # (once per machine, if not done yet)\n")
      cat("  git add .gitattributes\n")
      cat(
        "  git add",
        paste(
          shQuote(large_rel[seq_len(min(3, length(large_rel)))]),
          collapse = " "
        ),
        if (length(large_rel) > 3) "...",
        "\n"
      )
      cat("  git commit -m 'Track large files with Git LFS'\n")
    }
  }
}
