# Serve the Web export on http://localhost:<Port>/
# Usage: .\tools\serve.ps1 [-Port 8060]
param([int]$Port = 8060)
python "$PSScriptRoot\serve.py" --port $Port
