@echo off
setlocal
set "PATH=%LOCALAPPDATA%\Programs\Git\cmd;%LOCALAPPDATA%\Programs\gh\bin;%PATH%"
echo Pushing EmoLens to GitHub (https://github.com/Aarthika2006/EmoLens.git)...
git push -u origin main
echo.
pause
