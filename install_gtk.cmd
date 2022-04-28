if exist D:\a\_temp\Library\RGtk2\gtk\NUL exit 0

echo "Installing gtk ..."
curl -L -o gtk.zip http://ftp.gnome.org/pub/gnome/binaries/win64/gtk+/2.22/gtk+-bundle_2.22.1-20101229_win64.zip
md D:\a\_temp\GTK
md gtk
7z x gtk.zip -ox64 > nul
del gtk.zip
mv x64 gtk\x64

echo "Install RGtk2 ..."
curl -L -o RGtk2.zip https://github.com/lawremi/RGtk2/archive/refs/heads/master.zip
7z x RGtk2.zip > nul
del RGtk2.zip
set "GTK_PATH=%cd%\gtk\x64"
set "TMPDIR=D:\a\_temp\Rtmp"
R CMD build RGtk2-master\RGtk2
R CMD INSTALL RGtk2_2.20.40.tar.gz
Rscript -e "Sys.setenv(GTK_PATH = file.path(getwd(), 'gtk', 'x64')); install.packages('./RGtk2-master/RGtk2', repos = NULL, type = 'source')"

echo "Copying GTK binaries to RGtk2 package ..."
@REM mv gtk D:\a\_temp\Library\RGtk2\
