@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ============================================
echo   PBF 转离线矢量底图  (pbf\ -^> pmtiles\)
echo ============================================
echo.

rem --- 找便携 JDK 21 ---
set "JDKDIR="
for /d %%D in ("%~dp0jdk-21*") do set "JDKDIR=%%D"
if not defined JDKDIR ( echo [错误] 未找到 tools\jdk-21* 便携 JDK，请先按 README 安装。& pause & exit /b 1 )
set "JAVA=%JDKDIR%\bin\java.exe"
if not exist "%~dp0planetiler.jar" ( echo [错误] 未找到 tools\planetiler.jar。& pause & exit /b 1 )

rem --- 确保 pmtiles 输出目录存在 ---
if not exist "%~dp0pmtiles" md "%~dp0pmtiles"

rem --- 取 PBF：优先拖拽到本 bat 的文件；否则取 tools\pbf\ 里最新的 .pbf ---
set "PBF=%~1"
if not defined PBF (
  for /f "delims=" %%F in ('dir /b /a-d /o-d "%~dp0pbf\*.pbf" 2^>nul') do (
    set "PBF=%~dp0pbf\%%F"
    goto :gotpbf
  )
)
:gotpbf
if not defined PBF (
  echo [错误] 没找到 .pbf 文件。
  echo   把 BBBike 下载的 .pbf 放进 tools\pbf\ 目录再双击本 bat；
  echo   或直接把 .pbf 文件拖到本 bat 图标上松手。
  pause & exit /b 1
)

rem --- 输出名 = 文件名去掉 .osm.pbf；可手动改名 ---
for %%I in ("%PBF%") do set "NAME=%%~nI"
set "NAME=!NAME:.osm=!"
set /p "REGION=给离线包起个名字(直接回车用默认 [!NAME!] ): "
if not "!REGION!"=="" set "NAME=!REGION!"
set "OUT=%~dp0pmtiles\!NAME!.pmtiles"

echo.
echo 输入 PBF : %PBF%
echo 输出包   : %OUT%
echo 处理中... (区域大小不同，约几十秒到几分钟)
echo.

"%JAVA%" -Xmx4g ^
  -Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=10809 ^
  -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=10809 ^
  -jar "%~dp0planetiler.jar" --osm-path="%PBF%" --maxzoom=14 --output="%OUT%" --force --download

echo.
if exist "%OUT%" (
  echo [完成] 已生成: %OUT%
  echo 下一步：传到手机，App「我的 -^> 离线地图 -^> 导入」，地图页「图层」切到离线矢量底图。
) else (
  echo [失败] 未生成 .pmtiles，请翻看上面日志。
  echo 提示：若卡在下载基础数据，请确认 VPN/代理已开(127.0.0.1:10809)。
)
echo.
pause
