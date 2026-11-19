using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using Bastos.Native.Services;

int checks=0;
void Check(bool value,string name){if(!value)throw new Exception(name);checks++;Console.WriteLine("PASS: "+name);}
var source=new Uri("https://download.microsoft.com/fixture.iso");
Check(OfficialIsoLinkPolicy.ShouldRetry("WebViewUnavailable",0,true,false),"Stopped browser initialization failure restarts once");
foreach(string status in new[]{"LinkReady","MicrosoftError","SentinelRejected","Cancelled","Error"})
 Check(!OfficialIsoLinkPolicy.ShouldRetry(status,0,true,false),"No browser retry for "+status);
Check(!OfficialIsoLinkPolicy.ShouldRetry("WebViewUnavailable",1,true,false),"Browser retry is bounded");
Check(!OfficialIsoLinkPolicy.ShouldRetry("WebViewUnavailable",0,false,false),"A live worker is never restarted");
Check(!OfficialIsoLinkPolicy.ShouldRetry("WebViewUnavailable",0,true,true),"Cancellation prevents browser restart");
foreach(string bad in new[]{"http://download.microsoft.com/a.iso","https://microsoft.com.evil.test/a.iso","https://user@download.microsoft.com/a.iso","https://download.microsoft.com:9443/a.iso","https://example.test/a.iso"})
 Check(!OfficialIsoTransfer.IsMicrosoftUri(new Uri(bad)),"Untrusted source rejected: "+bad);
foreach(string bad in new[]{"https://download.microsoft.com/%2fsecret.iso","https://download.microsoft.com/a.exe","https://download.microsoft.com/%5csecret.iso"}){
 try{OfficialIsoTransfer.GetFileName(new Uri(bad));throw new Exception("Expected invalid name");}catch(InvalidDataException){Check(true,"Unsafe filename rejected");}
}
string root=Path.Combine(Path.GetTempPath(),"BASTOS-IsoTransfer-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
byte[] bytes=new byte[2*1024*1024];Encoding.ASCII.GetBytes("CD001").CopyTo(bytes,32769);
HttpResponseMessage Good(){var r=new HttpResponseMessage(HttpStatusCode.OK){Content=new ByteArrayContent(bytes)};r.Content.Headers.ContentType=new MediaTypeHeaderValue("application/octet-stream");return r;}
try{
 var one=await OfficialIsoTransfer.DownloadAsync(source,root,null,default,new Handler(_=>Good()));
 Check(File.Exists(one.Path) && one.Sha256==Convert.ToHexString(SHA256.HashData(bytes)),"Complete ISO committed with its actual SHA256");
 var two=await OfficialIsoTransfer.DownloadAsync(source,root,null,default,new Handler(_=>Good()));
 Check(two.Path!=one.Path && File.ReadAllBytes(one.Path).SequenceEqual(bytes),"Existing ISO is never overwritten");
 async Task Refused(Func<HttpResponseMessage> reply,string name){
  string folder=Path.Combine(root,Guid.NewGuid().ToString("N"));
  try{await OfficialIsoTransfer.DownloadAsync(source,folder,null,default,new Handler(_=>reply()));throw new Exception("Expected refusal: "+name);}
  catch(Exception e) when(e is InvalidDataException or IOException or HttpRequestException){Check(!Directory.EnumerateFiles(folder).Any(),name+"; no completed or partial file retained");}
 }
 await Refused(()=>{var r=Good();r.Content.Headers.ContentLength=bytes.Length+100;return r;},"Truncated response refused");
 await Refused(()=>{var r=Good();r.StatusCode=HttpStatusCode.PartialContent;return r;},"Unsolicited partial response refused");
 await Refused(()=>{var r=Good();r.Content.Headers.ContentType=new MediaTypeHeaderValue("text/html");return r;},"HTML error response refused");
 await Refused(()=>new HttpResponseMessage(HttpStatusCode.OK){Content=new ByteArrayContent(new byte[bytes.Length])},"Invalid image signature refused");
 await Refused(()=>new HttpResponseMessage(HttpStatusCode.Forbidden){Content=new StringContent("Forbidden")},"HTTP failure refused");
 var redirect=new Handler(_=>new HttpResponseMessage(HttpStatusCode.Redirect){Headers={Location=new Uri("https://example.test/a.iso")}});
 try{await OfficialIsoTransfer.DownloadAsync(source,Path.Combine(root,"redirect"),null,default,redirect);throw new Exception("Expected redirect refusal");}
 catch(InvalidDataException){Check(redirect.Requests==1,"Off-Microsoft redirect rejected before a second request");}
 using var cancelled=new CancellationTokenSource();cancelled.Cancel();
 var unopened=new Handler(_=>Good());
 try{await OfficialIsoTransfer.DownloadAsync(source,Path.Combine(root,"cancelled"),null,cancelled.Token,unopened);throw new Exception("Expected cancellation");}
 catch(OperationCanceledException){Check(unopened.Requests==0 && !Directory.Exists(Path.Combine(root,"cancelled")),"Pre-cancelled download performs no I/O or request");}
 using var during=new CancellationTokenSource(TimeSpan.FromMilliseconds(200));
 string partial=Path.Combine(root,"partial");
 var slow=new Handler(_=>new HttpResponseMessage(HttpStatusCode.OK){Content=new StreamContent(new WaitingStream())});
 try{await OfficialIsoTransfer.DownloadAsync(source,partial,null,during.Token,slow);throw new Exception("Expected streaming cancellation");}
 catch(OperationCanceledException){Check(!Directory.EnumerateFiles(partial).Any(),"In-flight cancellation removes the incomplete file cooperatively");}
 Check(!Directory.EnumerateFiles(root,"*.download",SearchOption.AllDirectories).Any(),"No temporary file left after terminal results");
 Console.WriteLine("PASS: "+checks+" ISO transfer checks; synthetic network only.");
}finally{Directory.Delete(root,true);}

sealed class Handler(Func<HttpRequestMessage,HttpResponseMessage> reply):HttpMessageHandler{
 public int Requests{get;private set;}
 protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token){Requests++;return Task.FromResult(reply(request));}
}
sealed class WaitingStream:Stream{
 public override bool CanRead=>true;public override bool CanSeek=>false;public override bool CanWrite=>false;public override long Length=>throw new NotSupportedException();public override long Position{get=>0;set=>throw new NotSupportedException();}
 public override async ValueTask<int> ReadAsync(Memory<byte> buffer,CancellationToken token=default){await Task.Delay(Timeout.Infinite,token);return 0;}
 public override int Read(byte[] b,int o,int c)=>throw new NotSupportedException();public override void Flush(){}public override long Seek(long o,SeekOrigin so)=>throw new NotSupportedException();public override void SetLength(long n)=>throw new NotSupportedException();public override void Write(byte[] b,int o,int c)=>throw new NotSupportedException();
}
