template <- readLines("index.template")

get_list <- function(dir) {
    path <- sprintf("s3://r.docker.stat.auckland.ac.nz/%s/", dir)
    cmd <- sprintf("aws --profile saml s3 ls %s", path)
    x <- system(cmd, intern = TRUE)
    x <- do.call(rbind,
        lapply(strsplit(x, " "),
            function(z) {
                data.frame(
                    date = ifelse
                )
                tail(z, 2)
            }
        )
    )
    colnames(x) <- c("size", "path")
    x <- as.data.frame(x)
    x$size <- suppressWarnings(as.integer(x$size))
    x
}
downloads_dir <- get_list("downloads")
