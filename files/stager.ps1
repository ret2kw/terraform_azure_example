wuauclt.exe /updatenow
choco install -y python3 --version=3.7.3
choco install vcredist140 -y
choco install git -y
choco install 7zip.install -y
choco install firefox -y 
choco install windows-sdk-10-version-1803-windbg -y
choco install dotpeek -y
choco install dnspy -y
choco install javadecompiler-gui -y
choco install cfr -y
#choco install classyshark -y
choco install jadx -y
choco install dex2jar -y
choco install apktool -y
choco install vscode-java-debug -y
choco install burp-suite-free-edition -y
choco install vscode -y
choco install sysinternals -y
choco install processhacker -y
choco install cygwin -y
choco install msys2 -y
choco install wireshark -y
choco install googlechrome -y
#choco install -y cmake --installargs 'ADD_CMAKE_TO_PATH=System'
#choco install -y visualstudio2019buildtools --package-parameters "--allWorkloads --includeRecommended --includeOptional --passive --locale en-US"

refreshenv
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

#we have to run ie to trigger MS updating the root CAs
"C:\Program Files\Internet Explorer\iexplore.exe" pypi.org
Start-Sleep -s 30
Get-Process iexplore | Stop-Process

python -m pip install frida-tools ipython jupyterlab pandas requests matplotlib seaborn aioserial
python -m pip install checksec.py pywinauto





