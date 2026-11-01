@echo off
setlocal
where py >nul 2>nul
if not errorlevel 1 (
    py -3 "%~dp0lootlog_exporter.py" --watch %*
) else (
    where python >nul 2>nul
    if errorlevel 1 (
        echo Python 3.9 or newer is required for the Lootlogs helper.
        echo Install Python, then run this file again.
        pause
        exit /b 1
    )
    python "%~dp0lootlog_exporter.py" --watch %*
)
if errorlevel 1 pause
