using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
[assembly: AssemblyTitle("Désinstallation BASTOS")]
[assembly: AssemblyVersion("7.120.141.0")]
[assembly: AssemblyFileVersion("7.120.141.0")]
static class Uninstall {
 [STAThread] static int Main(string[] args) {
  try {
   bool silent=false;string testRoot=null;
   for(int i=0;i<args.Length;i++){
    if(args[i]=="/silent")silent=true;
    else if(args[i]=="--test-root"&&i+1<args.Length)testRoot=Path.GetFullPath(args[++i]);
    else throw new ArgumentException("Argument inconnu.");
   }
   string root=Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
   string expected=Path.Combine(testRoot??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs"),"BASTOS");
   if(!String.Equals(Path.GetFullPath(root),expected,StringComparison.OrdinalIgnoreCase))throw new IOException("Ce programme doit être lancé depuis son installation BASTOS.");
   if(!silent&&MessageBox.Show("Retirer les fichiers de BASTOS et son raccourci ?\r\n\r\nVos données et sauvegardes restent conservées. Les réglages déjà appliqués à Windows ne sont pas automatiquement restaurés.","Désinstallation BASTOS",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)return 0;
   string temp=Path.Combine(Path.GetTempPath(),"BASTOS-Uninstall-"+Guid.NewGuid().ToString("N")+".ps1");
   using(var input=Assembly.GetExecutingAssembly().GetManifestResourceStream("Uninstall.ps1"))using(var output=new FileStream(temp,FileMode.CreateNew,FileAccess.Write,FileShare.None))input.CopyTo(output);
   string arguments="-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \""+temp+"\" -AppRoot \""+root+"\" -ParentId "+Process.GetCurrentProcess().Id;
   if(testRoot!=null)arguments+=" -TestRoot \""+testRoot.TrimEnd('\\')+"\"";
   Process.Start(new ProcessStartInfo(Path.Combine(Environment.SystemDirectory,"WindowsPowerShell\\v1.0\\powershell.exe"),arguments){UseShellExecute=false,CreateNoWindow=true});
   return 0;
  }catch(Exception ex){MessageBox.Show(ex.Message,"Désinstallation BASTOS",MessageBoxButtons.OK,MessageBoxIcon.Error);return 1;}
 }
}
