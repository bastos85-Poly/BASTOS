Set-StrictMode -Version Latest
if(-not ('BastosCompetitiveAudio' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class BastosCompetitiveAudio {
 [StructLayout(LayoutKind.Sequential)] public struct Key {public Guid fmt;public uint pid;public Key(string id,uint p){fmt=new Guid(id);pid=p;}}
 [StructLayout(LayoutKind.Explicit,Size=24)] public struct Value {[FieldOffset(0)]public ushort vt;[FieldOffset(8)]public uint number;[FieldOffset(8)]public IntPtr ptr;}
 [ComImport,Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface Enumerator {
  [PreserveSig]int EnumAudioEndpoints(int flow,uint state,out Devices devices);
  [PreserveSig]int GetDefaultAudioEndpoint(int flow,int role,out Device device);
  [PreserveSig]int GetDevice([MarshalAs(UnmanagedType.LPWStr)]string id,out Device device);
 }
 [ComImport,Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface Devices {
  [PreserveSig]int GetCount(out uint count);[PreserveSig]int Item(uint index,out Device device);
 }
 [ComImport,Guid("D666063F-1587-4E43-81F1-B948E807363F"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface Device {
  [PreserveSig]int Activate(ref Guid iid,uint context,IntPtr activation,[MarshalAs(UnmanagedType.IUnknown)]out object instance);
  [PreserveSig]int OpenPropertyStore(uint mode,out Store store);
  [PreserveSig]int GetId([MarshalAs(UnmanagedType.LPWStr)]out string id);
  [PreserveSig]int GetState(out uint state);
 }
 [ComImport,Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface Store {
  [PreserveSig]int GetCount(out uint count);[PreserveSig]int GetAt(uint i,out Key key);
  [PreserveSig]int GetValue(ref Key key,out Value value);
  [PreserveSig]int SetValue(ref Key key,ref Value value);[PreserveSig]int Commit();
 }
 [ComImport,Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface Client {
  [PreserveSig]int Initialize(int mode,uint flags,long duration,long periodicity,IntPtr format,IntPtr session);
  [PreserveSig]int GetBufferSize(out uint n);[PreserveSig]int GetStreamLatency(out long n);[PreserveSig]int GetCurrentPadding(out uint n);
  [PreserveSig]int IsFormatSupported(int mode,IntPtr format,out IntPtr closest);
 }
 [ComImport,Guid("F8679F50-850A-41CF-9C72-430F290290C8"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface Policy {
  [PreserveSig]int GetMixFormat([MarshalAs(UnmanagedType.LPWStr)]string id,out IntPtr format);
  [PreserveSig]int GetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)]string id,int defaultFormat,out IntPtr format);
  [PreserveSig]int ResetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)]string id);
  [PreserveSig]int SetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)]string id,IntPtr endpoint,IntPtr mix);
  [PreserveSig]int GetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)]string id,int defaultPeriod,out long period,out long minimum);
  [PreserveSig]int SetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)]string id,ref long period);
  [PreserveSig]int GetShareMode([MarshalAs(UnmanagedType.LPWStr)]string id,IntPtr mode);
  [PreserveSig]int SetShareMode([MarshalAs(UnmanagedType.LPWStr)]string id,IntPtr mode);
  [PreserveSig]int GetPropertyValue([MarshalAs(UnmanagedType.LPWStr)]string id,ref Key key,out Value value);
  [PreserveSig]int SetPropertyValue([MarshalAs(UnmanagedType.LPWStr)]string id,ref Key key,ref Value value);
 }
 [DllImport("ole32.dll")]static extern int PropVariantClear(ref Value value);
 static void Check(int hr){if(hr<0)Marshal.ThrowExceptionForHR(hr);}
 static Enumerator NewEnum(){return (Enumerator)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")));}
 static Policy NewPolicy(){return (Policy)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")));}
 static Key Fx=new Key("1da5d803-d492-4edd-8c23-e0c0ffee7f0e",5);
 static Key Spatial=new Key("63745869-983f-423b-9c94-5dbbd29da278",1);
 public class Record {public string Id,Name,Format;public uint? Effects,Spatial;public long Period,Minimum;}
 static string Format(Policy p,string id){IntPtr f;Check(p.GetDeviceFormat(id,0,out f));try{int length=18+(ushort)Marshal.ReadInt16(f,16);if(length>4096)throw new Exception("Format audio invalide");byte[] b=new byte[length];Marshal.Copy(f,b,0,length);return Convert.ToBase64String(b);}finally{Marshal.FreeCoTaskMem(f);}}
 static uint? Property(Policy p,string id,Key key){var e=NewEnum();Device d=null;Store store=null;try{Check(e.GetDevice(id,out d));Check(d.OpenPropertyStore(0,out store));Value v;Check(store.GetValue(ref key,out v));try{if(v.vt==0)return null;if(v.vt!=19)throw new Exception("Type de propriete audio non pris en charge");return v.number;}finally{PropVariantClear(ref v);}}finally{if(store!=null)Marshal.ReleaseComObject(store);if(d!=null)Marshal.ReleaseComObject(d);Marshal.ReleaseComObject(e);}} public static Record Read(string id){var e=NewEnum();var p=NewPolicy();Device d=null;Store store=null;try{Check(e.GetDevice(id,out d));string name=id;if(d.OpenPropertyStore(0,out store)>=0){Key k=new Key("a45c254e-df1c-4efd-8020-67d146a850e0",14);Value v;if(store.GetValue(ref k,out v)>=0){try{if(v.vt==31)name=Marshal.PtrToStringUni(v.ptr);}finally{PropVariantClear(ref v);}}}long period=0,min=0;p.GetProcessingPeriod(id,0,out period,out min);return new Record{Id=id,Name=name,Format=Format(p,id),Effects=Property(p,id,Fx),Spatial=Property(p,id,Spatial),Period=period,Minimum=min};}finally{if(store!=null)Marshal.ReleaseComObject(store);if(d!=null)Marshal.ReleaseComObject(d);Marshal.ReleaseComObject(p);Marshal.ReleaseComObject(e);}}
 public static string[] Ids(){var e=NewEnum();Devices ds=null;try{Check(e.EnumAudioEndpoints(2,1,out ds));uint count;Check(ds.GetCount(out count));var ids=new List<string>();for(uint n=0;n<count;n++){Device d;Check(ds.Item(n,out d));try{string id;Check(d.GetId(out id));ids.Add(id);}finally{Marshal.ReleaseComObject(d);}}return ids.ToArray();}finally{if(ds!=null)Marshal.ReleaseComObject(ds);Marshal.ReleaseComObject(e);}}
 static IntPtr Bytes(string data){byte[] b=Convert.FromBase64String(data);IntPtr p=Marshal.AllocCoTaskMem(b.Length);Marshal.Copy(b,0,p,b.Length);return p;}
 public static string DesiredFormat(string id){var record=Read(id);byte[] original=Convert.FromBase64String(record.Format);var e=NewEnum();Device d=null;object obj=null;try{Check(e.GetDevice(id,out d));Guid iid=new Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2");Check(d.Activate(ref iid,23,IntPtr.Zero,out obj));var c=(Client)obj;ushort channels=BitConverter.ToUInt16(original,2);ushort tag=BitConverter.ToUInt16(original,0);foreach(int candidate in new int[]{0,1,2}){int bits=candidate==0?24:candidate==1?32:16;int valid=candidate==1?24:bits;byte[] b=(byte[])original.Clone();Array.Copy(BitConverter.GetBytes(48000),0,b,4,4);Array.Copy(BitConverter.GetBytes((ushort)bits),0,b,14,2);ushort align=(ushort)(channels*bits/8);Array.Copy(BitConverter.GetBytes(align),0,b,12,2);Array.Copy(BitConverter.GetBytes(48000*(int)align),0,b,8,4);if(tag==65534&&b.Length>=40){Array.Copy(BitConverter.GetBytes((ushort)valid),0,b,18,2);Array.Copy(new Guid("00000001-0000-0010-8000-00aa00389b71").ToByteArray(),0,b,24,16);}else Array.Copy(BitConverter.GetBytes((ushort)1),0,b,0,2);IntPtr mem=Bytes(Convert.ToBase64String(b)),closest;int hr;try{hr=c.IsFormatSupported(1,mem,out closest);if(closest!=IntPtr.Zero)Marshal.FreeCoTaskMem(closest);}finally{Marshal.FreeCoTaskMem(mem);}if(hr==0)return Convert.ToBase64String(b);}throw new Exception("Aucun format PCM 48 kHz pris en charge; peripherique conserve.");}finally{if(obj!=null)Marshal.ReleaseComObject(obj);if(d!=null)Marshal.ReleaseComObject(d);Marshal.ReleaseComObject(e);}}
 public static void Set(string id,string setting,string value){var p=NewPolicy();try{if(setting=="Format"){IntPtr mem=Bytes(value);try{Check(p.SetDeviceFormat(id,mem,mem));}finally{Marshal.FreeCoTaskMem(mem);}}else if(setting=="Period"){long period=long.Parse(value);Check(p.SetProcessingPeriod(id,ref period));}else{Key key=setting=="Effects"?Fx:Spatial;Value v=string.IsNullOrEmpty(value)?new Value{vt=0}:new Value{vt=19,number=uint.Parse(value)};var e=NewEnum();Device d=null;Store store=null;try{Check(e.GetDevice(id,out d));Check(d.OpenPropertyStore(2,out store));Check(store.SetValue(ref key,ref v));Check(store.Commit());}finally{if(store!=null)Marshal.ReleaseComObject(store);if(d!=null)Marshal.ReleaseComObject(d);Marshal.ReleaseComObject(e);}}}finally{Marshal.ReleaseComObject(p);}}
}
'@
}
Export-ModuleMember -Function @()



