@echo off
setlocal
echo ========================================================
echo        EmoLens - GitHub Repository Creator & Pusher
echo ========================================================
echo.

:: Add Git and GitHub CLI to current PATH
set "PATH=%LOCALAPPDATA%\Programs\Git\cmd;%LOCALAPPDATA%\Programs\gh\bin;%PATH%"

echo [1/3] Checking Git and GitHub CLI...
where git >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Git not found. Please ensure Git is installed.
    pause
    exit /b 1
)

where gh >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] GitHub CLI (gh) not found.
    pause
    exit /b 1
)
echo [OK] Git and GitHub CLI are ready.
echo.

:: Check authentication
echo [2/3] Checking GitHub authentication status...
gh auth status >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo.
    echo -------------------------------------------------------------
    echo  You need to log in to GitHub once in your browser.
    echo  A code will appear below and your browser will open.
    echo  Paste the code and click 'Authorize'.
    echo -------------------------------------------------------------
    echo.
    gh auth login --web -h github.com -p https
)

echo.
echo [3/3] Creating repository 'EmoLens' on GitHub and pushing code...
gh repo create EmoLens --public --source=. --remote=origin --push 2>nul
if %ERRORLEVEL% neq 0 (
    echo Repository might already exist on GitHub. Pushing changes directly...
    git push -u origin main
)

echo.
echo ========================================================
echo  SUCCESS! Your code is now live on GitHub:
echo  https://github.com/Aarthika2006/EmoLens
echo ========================================================
echo.
pause
