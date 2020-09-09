install.packages("glue")
install.packages("gdata")

template <- paste(readLines("index.template"), collapse = "\n")
exclude <- c("index.html", "windows_versions.txt")

get_list <- function(dir) {
    path <- sprintf("s3://r.docker.stat.auckland.ac.nz/%s/", dir)
    cmd <- sprintf("aws --profile saml s3 ls %s", path)
    x <- system(cmd, intern = TRUE)
    x <- do.call(rbind,
        lapply(strsplit(x, "[ ]+"),
            function(z) {
                if (grepl("PRE", z[2])) {
                    c(NA, NA, z[3])
                } else {
                    c(paste(z[1], z[2]), z[3:4])
                }
            }
        )
    )
    data.frame(
        date = as.POSIXct(x[,1]),
        size = as.integer(x[,2]),
        path = x[,3]
    )
}

html_table <- function(x) {
    tmp <- "<tr><td class=\"nopad\"><img src=\"/icons/{type}.png\"></td><td><a href=\"{path}\">{path}</a></td><td>{date}</td><td>{size}</td></tr>"
    x <- x[!x$path %in% exclude,]
    rows <- sapply(seq_len(nrow(x)),
        function(i) {
            type <- ifelse(is.na(x[i, "date"]), "folder", "file")
            path <- x[i, "path"]
            date <- ifelse(type == "folder", "-", x[i, "date"])
            size <- ifelse(type == "folder", "-", gdata::humanReadable(x[i, "size"]))
            glue::glue(tmp)
        }
    )
    paste(rows, collapse = "\n")
}

html_page <- function(dir) {
    x <- get_list(dir)
    tbl <- html_table(x)
    html <- glue::glue(template)
    dir.create(dir, recursive = TRUE)
    writeLines(file.path(dir, "index.html"), html)
}

ca <- commandArgs(TRUE)
sapply(ca, html_page)
