ca <- commandArgs(trailingOnly = TRUE)

# Delete all nightly builds based on earlier versions (< x.y.z)
# And only keep the 7 most recent

delete_files <- function(ca) {
    if (length(ca) == 0) return()
    file_list <- ca[1]

}

delete_files(ca)
