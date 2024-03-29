echo "Installing gtk ..."
curl -L -o gtk.zip http://ftp.gnome.org/pub/gnome/binaries/win64/gtk+/2.22/gtk+-bundle_2.22.1-20101229_win64.zip
md D:\a\_temp\GTK
7z x gtk.zip -ox64 > nul
del gtk.zip
cp -r x64 D:\a\_temp\GTK\x64
md gtk
mv x64 gtk

if not exist D:\a\_temp\Library\RGtk2\NUL (
    echo "Install RGtk2 ..."
    curl -L -o RGtk2.zip https://github.com/lawremi/RGtk2/archive/refs/heads/master.zip
    7z x RGtk2.zip > nul
    del RGtk2.zip
    rm RGtk2-master\RGtk2\src\RGtk2
    ln -s ..\inst\include\RGtk2 RGtk2-master\RGtk2\src\RGtk2
    R CMD build RGtk2-master\RGtk2
    R CMD INSTALL --no-multiarch RGtk2_2.20.40.tar.gz

    echo "Copying GTK binaries to RGtk2 package ..."
    mv gtk D:\a\_temp\Library\RGtk2\
)

if not exist D:\a\_temp\Library\cairoDevice\NUL (
    echo "Install cairoDevice ..."
    curl -L -o cairoDevice.zip https://github.com/tmelliott/cairoDevice/archive/refs/heads/master.zip
    7z x cairoDevice.zip > nul
    del cairoDevice.zip
    R CMD build cairoDevice-master
    R CMD INSTALL --no-multiarch cairoDevice_2.31.tar.gz
)
