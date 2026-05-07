@echo off
chcp 65001 >nul 2>&1
title Meeting Notes App - Force Reinstall

echo.
echo ================================================
echo   Force Reinstall — deleting .venv
echo ================================================
echo.

if exist "%~dp0.venv" (
    echo   Removing existing .venv...
    rmdir /s /q "%~dp0.venv"
    echo   [OK] Removed
) else (
    echo   [--] No .venv found, nothing to remove
)

echo.
echo   Starting fresh install via start.bat...
echo.
call "%~dp0start.bat"
