@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0buildDockerImage_u24_docker.ps1" %*
