if exist D:\a\_temp\Library\RGtk2\gtk\NUL exit 0

echo "Installing gtk ..."
curl -L -o gtk.zip http://ftp.gnome.org/pub/gnome/binaries/win64/gtk+/2.22/gtk+-bundle_2.22.1-20101229_win64.zip
md D:\a\_temp\GTK
md gtk
7z x gtk.zip -ogtk > nul
del gtk.zip

echo "Install RGtk2 ..."
Rscript -e "Sys.setenv(GTK_PATH = file.path(getwd(), 'gtk')); install.packages('RGtk2', repos = 'https://r.docker.stat.auckland.ac.nz')"

echo "Copying GTK binaries to RGtk2 package ..."
mv gtk D:\a\_temp\Library\RGtk2\
