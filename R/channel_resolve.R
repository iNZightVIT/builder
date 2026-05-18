# Package resolution for iNZight build channels.

DEFAULT_ORG <- "iNZightVIT"

pkg_name_from_spec <- function(spec) {
  spec <- trimws(spec)
  if (!nzchar(spec)) {
    return(NA_character_)
  }
  spec <- sub("@.*$", "", spec)
  parts <- strsplit(spec, "/", fixed = TRUE)[[1]]
  parts[[length(parts)]]
}

normalize_stable_spec <- function(pkg, default_org = DEFAULT_ORG) {
  pkg <- trimws(pkg)
  if (!nzchar(pkg)) {
    return(NA_character_)
  }
  at <- regexpr("@", pkg, fixed = TRUE)[1L]
  if (at > 0L) {
    repo_spec <- substring(pkg, 1L, at - 1L)
    ref <- substring(pkg, at + 1L)
    parts <- strsplit(repo_spec, "/", fixed = TRUE)[[1L]]
    if (length(parts) == 1L) {
      owner <- default_org
      name <- parts[[1L]]
    } else {
      owner <- parts[[1L]]
      name <- paste(parts[-1L], collapse = "/")
    }
    return(sprintf("%s/%s@%s", owner, name, ref))
  }
  parts <- strsplit(pkg, "/", fixed = TRUE)[[1L]]
  if (length(parts) == 1L) {
    sprintf("%s/%s", default_org, parts[[1L]])
  } else {
    sprintf("%s/%s", parts[[1L]], paste(parts[-1L], collapse = "/"))
  }
}

expand_nightly_github_pkg <- function(pkg) {
  pkg <- trimws(pkg)
  if (!nzchar(pkg)) {
    return(NA_character_)
  }

  at <- regexpr("@", pkg, fixed = TRUE)[1L]
  if (at > 0L) {
    return(normalize_stable_spec(pkg))
  }

  parts <- strsplit(pkg, "/", fixed = TRUE)[[1L]]
  if (length(parts) == 1L) {
    owner <- DEFAULT_ORG
    name <- parts[[1L]]
  } else {
    owner <- parts[[1L]]
    name <- paste(parts[-1L], collapse = "/")
  }

  if (!requireNamespace("httr", quietly = TRUE) || !requireNamespace("lubridate", quietly = TRUE)) {
  }

  url <- sprintf("https://api.github.com/repos/%s/%s/branches", owner, name)
  x <- httr::GET(url)
  branches <- httr::content(x, as = "parsed")
  if (httr::http_error(x) || (is.list(branches) && !is.null(branches$message))) {
    err <- if (is.list(branches) && !is.null(branches$message)) {
      as.character(branches$message)[1L]
    } else {
      paste0("HTTP ", httr::status_code(x))
    }
    warning("Could not list branches for ", owner, "/", name, ": ", err, call. = FALSE)
    return(NA_character_)
  }
  if (!length(branches)) {
    warning("No branches returned for ", owner, "/", name, call. = FALSE)
    return(NA_character_)
  }

  branch_names <- vapply(branches, function(b) {
    n <- b$name
    if (is.null(n) || !nzchar(n)) NA_character_ else as.character(n)[1L]
  }, character(1L))
  names(branches) <- branch_names

  branch <- NULL
  for (cand in c("develop", "main", "master")) {
    if (cand %in% branch_names) {
      branch <- cand
      break
    }
  }
  if (is.null(branch)) {
    ok <- branch_names[!is.na(branch_names) & nzchar(branch_names)]
    if (!length(ok)) {
      warning("No usable branch names for ", owner, "/", name, call. = FALSE)
      return(NA_character_)
    }
    branch <- ok[[1L]]
  }

  release_branches <- branches[grepl("release", branch_names, ignore.case = TRUE)]
  if (length(release_branches)) {
    dev_branch <- branches[[branch]]
    dev_date <- httr::content(httr::GET(dev_branch$commit$url))$commit$author$date |>
      lubridate::ymd_hms()

    release_dates <- lapply(release_branches, function(b) {
      data.frame(
        branch = b$name,
        date = httr::content(httr::GET(b$commit$url))$commit$author$date |>
          lubridate::ymd_hms()
      )
    })
    release_dates <- do.call(rbind, release_dates)
    release_row <- release_dates[which.max(release_dates$date), , drop = FALSE]
    if (release_row$date > dev_date) {
      branch <- sprintf("refs/heads/%s", release_row$branch)
    }
  }

  sprintf("%s/%s@%s", owner, name, branch)
}

resolve_channel_packages <- function(deps) {
  pkgs <- deps$packages
  ctype <- deps$channel_type
  if (ctype %in% c("stable", "pinned") || isTRUE(deps$overrides_only)) {
    resolved <- vapply(pkgs, normalize_stable_spec, character(1))
  } else {
    resolved <- vapply(pkgs, expand_nightly_github_pkg, character(1))
  }
  resolved <- resolved[!is.na(resolved) & nzchar(resolved)]
  if (!length(resolved)) {
    stop("No packages resolved for channel ", deps$channel, call. = FALSE)
  }
  unique(resolved)
}
