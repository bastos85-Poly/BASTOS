Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Initialize-BastosWimApi {
    if('Bastos.WimMetadata' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;


namespace Bastos {
 public static class WimMetadata {
  [DllImport("wimgapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern IntPtr WIMCreateFile(string path,uint access,uint disposition,uint flags,uint compression,out uint result);
  [DllImport("wimgapi.dll", SetLastError=true)]
  static extern bool WIMGetImageInformation(IntPtr handle,out IntPtr data,out uint size);
  [DllImport("wimgapi.dll", SetLastError=true)]
  static extern bool WIMSetImageInformation(IntPtr handle,IntPtr data,uint size);
  [DllImport("wimgapi.dll", SetLastError=true)]
  static extern bool WIMCloseHandle(IntPtr handle);
  [DllImport("wimgapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern bool WIMSetTemporaryPath(IntPtr handle,string path);
  [DllImport("wimgapi.dll", SetLastError=true)]
  static extern IntPtr WIMLoadImage(IntPtr handle,uint index);
  [DllImport("wimgapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern bool WIMExtractImagePath(IntPtr image,string source,string destination,uint flags);
  [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr data);
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
  [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool LookupPrivilegeValue(string system,string name,out long luid);
  [StructLayout(LayoutKind.Sequential,Pack=1)] struct Privilege {public uint Count;public long Luid;public uint Attributes;}
  [DllImport("advapi32.dll",SetLastError=true)] static extern bool AdjustTokenPrivileges(IntPtr token,bool disable,ref Privilege privilege,uint length,IntPtr previous,IntPtr needed);
  static void EnableImagingPrivileges() {
   IntPtr token;if(!OpenProcessToken(GetCurrentProcess(),0x28,out token))throw new Win32Exception(Marshal.GetLastWin32Error());
   try {foreach(string name in new[]{"SeBackupPrivilege","SeRestorePrivilege"}) {
    long luid;if(!LookupPrivilegeValue(null,name,out luid))throw new Win32Exception(Marshal.GetLastWin32Error());
    Privilege p=new Privilege{Count=1,Luid=luid,Attributes=2};
    if(!AdjustTokenPrivileges(token,false,ref p,0,IntPtr.Zero,IntPtr.Zero))throw new Win32Exception(Marshal.GetLastWin32Error());
    int error=Marshal.GetLastWin32Error();if(error!=0)throw new Win32Exception(error);
   }}finally{CloseHandle(token);}
  }
  static IntPtr Open(string path,bool write) {
   uint result; IntPtr h=WIMCreateFile(path,write?0xC0000000u:0x80000000u,3,0,0,out result);
   if(h==IntPtr.Zero || h==new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error(),"Ouverture WIM impossible");
   return h;
  }
  public static string Read(string path) {
   IntPtr h=Open(path,false),p=IntPtr.Zero;
   try {uint n;if(!WIMGetImageInformation(h,out p,out n))throw new Win32Exception(Marshal.GetLastWin32Error());
    return Marshal.PtrToStringUni(p,(int)n/2).Trim('\0','\uFEFF');
   } finally {if(p!=IntPtr.Zero)LocalFree(p);WIMCloseHandle(h);}
  }
  public static void WriteImage(string path,uint index,string xml) {
   IntPtr h=Open(path,true),image=IntPtr.Zero,p=IntPtr.Zero;
   try {
    if(!WIMSetTemporaryPath(h,System.IO.Path.GetTempPath()))throw new Win32Exception(Marshal.GetLastWin32Error());
    image=WIMLoadImage(h,index);
    if(image==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error());
    string text="\uFEFF"+xml; p=Marshal.StringToHGlobalUni(text);
    if(!WIMSetImageInformation(image,p,(uint)((text.Length+1)*2)))throw new Win32Exception(Marshal.GetLastWin32Error());
   }finally {if(p!=IntPtr.Zero)Marshal.FreeHGlobal(p);if(image!=IntPtr.Zero)WIMCloseHandle(image);WIMCloseHandle(h);}
  }
  public static void Extract(string path,uint index,string source,string destination,string temporaryPath) {
   EnableImagingPrivileges();
   IntPtr h=Open(path,false),image=IntPtr.Zero;
   try {
    if(!WIMSetTemporaryPath(h,temporaryPath))throw new Win32Exception(Marshal.GetLastWin32Error());
    image=WIMLoadImage(h,index);
    if(image==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error());
    if(!WIMExtractImagePath(image,source,destination,0))throw new Win32Exception(Marshal.GetLastWin32Error());
   }finally {if(image!=IntPtr.Zero)WIMCloseHandle(image);WIMCloseHandle(h);}
  }
 }
}
'@
}
function Get-BastosWimMetadata {
    param([Parameter(Mandatory)][string]$ImagePath)
    Initialize-BastosWimApi
    [xml][Bastos.WimMetadata]::Read([IO.Path]::GetFullPath($ImagePath))
}
function Assert-BastosWimSelection {
    param([Parameter(Mandatory)][xml]$Metadata,[Parameter(Mandatory)][int]$ImageIndex,[Parameter(Mandatory)][string]$EditionId)
    $node=$Metadata.SelectSingleNode("/WIM/IMAGE[@INDEX='$ImageIndex']")
    if(-not $node){throw "Index $ImageIndex absent du catalogue WIM."}
    $edition=$node.SelectSingleNode('WINDOWS/EDITIONID')
    $flags=$node.SelectSingleNode('FLAGS')
    $installation=$node.SelectSingleNode('WINDOWS/INSTALLATIONTYPE')
    $arch=$node.SelectSingleNode('WINDOWS/ARCH')
    $build=$node.SelectSingleNode('WINDOWS/VERSION/BUILD')
    $languages=$node.SelectSingleNode('WINDOWS/LANGUAGES/DEFAULT')
    if(-not $edition -or $edition.InnerText -ne $EditionId -or
       -not $flags -or $flags.InnerText -ne $EditionId -or
       -not $installation -or $installation.InnerText -ne 'Client' -or
       -not $arch -or $arch.InnerText -ne '9' -or
       -not $build -or [int]$build.InnerText -lt 22000 -or
       -not $languages -or [string]::IsNullOrWhiteSpace($languages.InnerText)){
        throw "Catalogue WIM incomplet ou divergent pour l index $ImageIndex ($EditionId). Reprepare l image depuis l ISO Microsoft avant de reinstaller. Aucun effacement autorise."
    }
}
function Restore-BastosWimWindowsMetadata {
    param([Parameter(Mandatory)][string]$ImagePath,[Parameter(Mandatory)][int]$ImageIndex,[Parameter(Mandatory)][xml]$OriginalMetadata)
    $original=$OriginalMetadata.SelectSingleNode("/WIM/IMAGE[@INDEX='$ImageIndex']/WINDOWS")
    if(-not $original){throw 'Metadonnees Windows originales absentes.'}
    $current=Get-BastosWimMetadata -ImagePath $ImagePath
    $image=$current.SelectSingleNode("/WIM/IMAGE[@INDEX='$ImageIndex']")
    if(-not $image){throw 'Index disparu apres nettoyage WIM.'}
    $old=$image.SelectSingleNode('WINDOWS')
    $replacement=$current.ImportNode($original,$true)
    if($old){[void]$image.ReplaceChild($replacement,$old)}else{[void]$image.AppendChild($replacement)}
    # A container handle accepts the call but does not persist per-image fields.
    # Write the IMAGE element through the selected WIMLoadImage handle instead.
    [Bastos.WimMetadata]::WriteImage([IO.Path]::GetFullPath($ImagePath),[uint32]$ImageIndex,$image.OuterXml)
    $verified=Get-BastosWimMetadata -ImagePath $ImagePath
    if($verified.SelectSingleNode("/WIM/IMAGE[@INDEX='$ImageIndex']/WINDOWS").OuterXml -ne $original.OuterXml){throw 'Restauration des metadonnees WIM non conforme.'}
}
function Assert-BastosBootAuthorization {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][ValidatePattern('^Attempt-[0-9a-fA-F]{32}$')][string]$AttemptId)
    foreach($name in @('BASTOS-ACTIVE-ATTEMPT.txt','BASTOS-AUTO-REINSTALL.token','BASTOS-BOOT-MODE.txt')){
        if(-not(Test-Path -LiteralPath (Join-Path $Root $name) -PathType Leaf)){throw "Autorisation incomplete : $name absent. Redemarrage refuse."}
    }
    $active=[IO.File]::ReadAllText((Join-Path $Root 'BASTOS-ACTIVE-ATTEMPT.txt')).Trim()
    $mode=[IO.File]::ReadAllText((Join-Path $Root 'BASTOS-BOOT-MODE.txt')).Trim()
    $token=[IO.File]::ReadAllText((Join-Path $Root 'BASTOS-AUTO-REINSTALL.token')).Trim()
    if($active -ne $AttemptId -or $mode -ne ('BOOTONCE|'+$AttemptId) -or [string]::IsNullOrWhiteSpace($token) -or
       (Test-Path -LiteralPath (Join-Path $Root 'BASTOS-DIAGNOSTIC-ONLY.token'))){throw 'Autorisation BootOnce incoherente. Redemarrage refuse.'}
}
function Test-BastosWimCachedAnswers {
    param([Parameter(Mandatory)][string]$ImagePath,[Parameter(Mandatory)][int]$ImageIndex)
    Initialize-BastosWimApi
    $temporary=Join-Path $env:TEMP ('BASTOS-WimAnswers-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporary -Force|Out-Null
    try{
        foreach($relative in @('\Windows\Panther\unattend.xml','\Windows\Panther\Unattend\Unattend.xml')){
            try{
                [Bastos.WimMetadata]::Extract([IO.Path]::GetFullPath($ImagePath),[uint32]$ImageIndex,$relative,(Join-Path $temporary 'unattend.xml'),$temporary)
                return $true
            }catch{
                $native=$_.Exception
                while($native.InnerException){$native=$native.InnerException}
                if($native -isnot [ComponentModel.Win32Exception] -or $native.NativeErrorCode -notin @(2,3)){throw}
            }
        }
        return $false
    }finally{
        $resolved=[IO.Path]::GetFullPath($temporary)
        if((Split-Path -Parent $resolved) -ne [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')){throw 'Nettoyage temporaire hors du dossier TEMP refuse.'}
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
function Get-BastosImageUILanguage {
    param([Parameter(Mandatory)][xml]$Metadata,[Parameter(Mandatory)][int]$ImageIndex,[string]$PreferredLanguage)
    $languages=$Metadata.SelectSingleNode("/WIM/IMAGE[@INDEX='$ImageIndex']/WINDOWS/LANGUAGES")
    if(-not $languages){throw 'Langues de l image Windows absentes.'}
    $available=@($languages.SelectNodes('LANGUAGE')|ForEach-Object{$_.InnerText})
    if($PreferredLanguage -in $available){return $PreferredLanguage}
    $default=$languages.SelectSingleNode('DEFAULT')
    if(-not $default -or $default.InnerText -notin $available){throw 'Langue par defaut de l image Windows invalide.'}
    return $default.InnerText
}
Export-ModuleMember -Function Get-BastosWimMetadata,Assert-BastosWimSelection,Restore-BastosWimWindowsMetadata,Assert-BastosBootAuthorization,Test-BastosWimCachedAnswers,Get-BastosImageUILanguage
