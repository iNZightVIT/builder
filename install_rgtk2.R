options(
    repos = c(
        "https://r.docker.stat.auckland.ac.nz", # for some packages like gWidgets, etc ...
        "https://cran.rstudio.com"
    ),
    install.packages.compile.from.source = "never"
)

if (!requireNamespace('RGtk2', quietly = TRUE)) 
    install.packages("RGtk2")
if (!requireNamespace('cairoDevice', quietly = TRUE)) 
    install.packages("cairoDevice")
