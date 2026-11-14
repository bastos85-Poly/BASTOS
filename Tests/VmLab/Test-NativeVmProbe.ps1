param([Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory $OutputDirectory -Force|Out-Null
$exe=Join-Path $OutputDirectory 'NativeProbe-Fixtures.exe'
& (Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe') /nologo /target:exe /platform:x64 /optimize+ /debug- /reference:System.Management.dll /reference:System.Web.Extensions.dll /reference:System.Windows.Forms.dll /reference:Microsoft.CSharp.dll ('/out:'+$exe) (Join-Path $PSScriptRoot 'Probe/NativeVmProbe.cs')
if($LASTEXITCODE -ne 0){throw 'Native probe fixture compilation failed.'}
& $exe --self-test
if($LASTEXITCODE -ne 0){throw 'Native probe guard fixtures failed.'}
