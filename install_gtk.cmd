@echo off
cd /d "%~dp0"
Rscript install_gtk.R
if errorlevel 1 exit /b 1
