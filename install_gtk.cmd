echo "Installing gtk ..."
curl -L -o gtk.zip http://ftp.gnome.org/pub/gnome/binaries/win64/gtk+/2.22/gtk+-bundle_2.22.1-20101229_win64.zip
md D:\a\_temp\GTK
md gtk
7z x gtk.zip -oD:\a\_temp\GTK > nul
7z x gtk.zip -ogtk > nul
del gtk.zip

if exist D:\a\_temp\Library\RGtk2\gtk\NUL exit 0
echo "Install RGtk2 ..."
R CMD INSTALL library/RGtk2

echo "Copying GTK binaries to RGtk2 package ..."
mv gtk D:\a\_temp\Library\RGtk2\
