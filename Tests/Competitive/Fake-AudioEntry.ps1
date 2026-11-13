param([string]$Worker,[string]$Action,[string]$ResultPath)
Add-Type @'
using System;using System.IO;
public static class BastosCompetitiveAudio {
 const string Root="C:\\BastosCompetitiveTest\\AudioFixture";
 public class Record {public string Id="Test-Endpoint",Name="Controlled test endpoint",Format;public uint? Effects,Spatial;public long Period,Minimum=10000;}
 static string DefaultFormat(){byte[] b=new byte[18];Array.Copy(BitConverter.GetBytes(44100),0,b,4,4);return Convert.ToBase64String(b);}
 static string Get(string n,string d){Directory.CreateDirectory(Root);string p=Path.Combine(Root,n);return File.Exists(p)?File.ReadAllText(p):d;}
 public static string[] Ids(){return new string[]{"Test-Endpoint"};}
 public static Record Read(string id){return new Record{Format=Get("Format",DefaultFormat()),Effects=uint.Parse(Get("Effects","0")),Spatial=uint.Parse(Get("Spatial","1")),Period=long.Parse(Get("Period","80000"))};}
 public static string DesiredFormat(string id){byte[] b=Convert.FromBase64String(DefaultFormat());Array.Copy(BitConverter.GetBytes(48000),0,b,4,4);return Convert.ToBase64String(b);}
 public static void Set(string id,string setting,string value){Directory.CreateDirectory(Root);File.WriteAllText(Path.Combine(Root,setting),value);}
}
'@
& $Worker -Action $Action -Id audio-game -ResultPath $ResultPath

