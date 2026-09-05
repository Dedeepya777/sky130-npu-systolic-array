@echo off
setlocal enabledelayedexpansion

REM Navigate to project root directory
set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%.."

echo ================================================================
echo  COS231 Research: 4x4 Weight-Stationary NPU Simulation Runner
echo ================================================================

REM Check if iverilog is in PATH or conda environment
where iverilog >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    if exist "%USERPROFILE%\anaconda3\envs\eda\Library\bin\iverilog.exe" (
        echo [INFO] Adding conda eda environment to PATH...
        set "PATH=%USERPROFILE%\anaconda3\envs\eda\Library\mingw-w64\bin;%USERPROFILE%\anaconda3\envs\eda\Library\bin;%USERPROFILE%\anaconda3\envs\eda\bin;!PATH!"
    ) else (
        echo [ERROR] iverilog not found in PATH or standard conda environment.
        echo Please activate your EDA environment or install Icarus Verilog.
        exit /b 1
    )
)

if not exist "sim" mkdir sim

echo [STEP 1/2] Compiling Verilog RTL and Testbench...
iverilog -Wall -s npu_tb -o sim/npu_sim.vvp rtl/mac.v rtl/processing_element.v rtl/systolic_array.v rtl/npu_top.v tb/npu_tb.v

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Compilation failed!
    exit /b %ERRORLEVEL%
)
echo [STEP 1/2] Compilation successful!

echo [STEP 2/2] Running Simulation...
vvp sim/npu_sim.vvp

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Simulation encountered errors!
    exit /b %ERRORLEVEL%
)

echo.
echo [COMPLETE] Simulation finished. Waveform written to sim/npu_sim.vcd
echo To view waveforms: gtkwave sim/npu_sim.vcd
endlocal
