// Harmless synthetic network probe; never executes or contacts Claude.
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Net.Security;
using System.Text;
using System.Web.Script.Serialization;
using System.Diagnostics;
class ClaudeNetworkProbe {
    static int Main(string[] args){
        if(args.Length!=6)return 2;
        string mode=args[0],address=args[1],output=args[5];int port=int.Parse(args[2]),index=int.Parse(args[3]);
        var watch=Stopwatch.StartNew();object result;
        try {
            IPAddress ip=IPAddress.Parse(address);
            if(!(ip.Equals(IPAddress.Loopback)||ip.Equals(IPAddress.IPv6Loopback)||address=="1.1.1.1"||address.StartsWith("fe80::1%")))throw new InvalidOperationException("Probe destination outside approved neutral scope");
            bool udp=mode=="udp";using(var socket=new Socket(ip.AddressFamily,udp?SocketType.Dgram:SocketType.Stream,udp?ProtocolType.Udp:ProtocolType.Tcp)){
                if(index>0)socket.SetSocketOption(ip.AddressFamily==AddressFamily.InterNetwork?SocketOptionLevel.IP:SocketOptionLevel.IPv6,(SocketOptionName)31,ip.AddressFamily==AddressFamily.InterNetwork?IPAddress.HostToNetworkOrder(index):index);
                if(args[4]!="-")socket.Bind(new IPEndPoint(IPAddress.Parse(args[4]),0));
                var task=socket.BeginConnect(new IPEndPoint(ip,port),null,null);
                if(!task.AsyncWaitHandle.WaitOne(4000))throw new TimeoutException("Connect timeout");socket.EndConnect(task);
                string detail="Connected";
                // A non-empty datagram is required: Windows may optimize away a zero-byte send.
                if(udp){int sent=socket.Send(new byte[]{0});detail="One-byte synthetic UDP accepted by socket: "+sent;}
                if(mode=="proxy"){
                    socket.ReceiveTimeout=6000;socket.SendTimeout=6000;
                    using(var stream=new NetworkStream(socket,false)){
                        byte[] connect=Encoding.ASCII.GetBytes("CONNECT www.cloudflare.com:443 HTTP/1.1\r\nHost: www.cloudflare.com:443\r\n\r\n");stream.Write(connect,0,connect.Length);
                        var head=new StringBuilder();while(head.Length<4096&&!head.ToString().EndsWith("\r\n\r\n")){int b=stream.ReadByte();if(b<0)throw new IOException("Proxy closed");head.Append((char)b);}
                        if(!head.ToString().StartsWith("HTTP/1.1 200"))throw new IOException("Proxy rejected CONNECT");
                        using(var ssl=new SslStream(stream,false)){ssl.ReadTimeout=6000;ssl.WriteTimeout=6000;ssl.AuthenticateAsClient("www.cloudflare.com",null,System.Security.Authentication.SslProtocols.Tls12,false);byte[] get=Encoding.ASCII.GetBytes("GET /cdn-cgi/trace HTTP/1.1\r\nHost: www.cloudflare.com\r\nConnection: close\r\n\r\n");ssl.Write(get,0,get.Length);var text=new StringBuilder();byte[] buffer=new byte[4096];int read;while((read=ssl.Read(buffer,0,buffer.Length))>0){text.Append(Encoding.UTF8.GetString(buffer,0,read));if(text.Length>32768)throw new IOException("Oversize response");}if(!text.ToString().StartsWith("HTTP/1.1 200"))throw new IOException("Neutral HTTPS failed");detail="TLS-validated neutral HTTPS via local proxy succeeded";}
                    }
                }
                result=new {Status=udp?"SEND_ACCEPTED":"CONNECTED",Mode=mode,Address=address,Port=port,InterfaceIndex=index,Detail=detail,DurationMs=watch.ElapsedMilliseconds};
            }
        }catch(SocketException e){result=new {Status="SOCKET_ERROR",Mode=mode,Address=address,Port=port,InterfaceIndex=index,NativeError=e.NativeErrorCode,SocketError=e.SocketErrorCode.ToString(),DurationMs=watch.ElapsedMilliseconds};}
        catch(Exception e){result=new{Status="ERROR",Mode=mode,Address=address,Error=e.GetType().Name+": "+e.Message,DurationMs=watch.ElapsedMilliseconds};}
        File.WriteAllText(output,new JavaScriptSerializer().Serialize(result),new UTF8Encoding(false));return 0;
    }
}
