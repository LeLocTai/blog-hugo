@echo off

for /f "delims=[] tokens=2" %%a in ('ping -4 -n 1 %ComputerName% ^| findstr [') do set NetworkIP=%%a

hugo server --buildDrafts --buildFuture --bind=0.0.0.0 --baseURL="http://%NetworkIP%/"