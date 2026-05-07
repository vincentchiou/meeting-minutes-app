@echo off
chcp 65001 >nul 2>&1
title Meeting Notes App - Force Reinstall

echo.
echo ================================================
echo   Meeting Notes APP - Force Reinstall
echo ================================================
echo.
echo   This will delete .venv and reinstall everything.
echo.

if exist "%~dp0.venv" (
    echo   Removing .venv...
    rmdir /s /q "%~dp0.venv"
    echo   [OK] Removed
) else (
    echo   [--] No .venv found
)

echo.
echo   Starting fresh install via start.bat...
echo.
call "%~dp0start.bat"
