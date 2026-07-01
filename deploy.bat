@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================
echo    Hexo Blog Deploy
echo ============================================
echo.

echo [1/3] Commit source...
git add .
git commit -m "deploy: %date:~0,10% %time:~0,8%" 2>nul

echo.
echo [2/3] Clean...
npx hexo clean

echo.
echo [3/3] Deploy...
npx hexo deploy

echo.
echo ============================================
echo    Done!
echo ============================================
pause
