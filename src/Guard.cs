using System;
using System.IO;
using System.Text;
using System.Linq;
using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

// Always-on IFEO gate. The desktop pet has no authority to clear it.
class BookGuard {
    const string Key = @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\Claude.exe";
    static readonly string Root = AppDomain.CurrentDomain.BaseDirectory;
    static readonly string Data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "ShuniangGuard");
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer();
    static string Self { get { return Application.ExecutablePath; } }
    static string Blocker { get { return Quote(Self)+" --intercept"; } }
    public class Check { public string id; public bool ok; public string message; }
    public class Evidence { public int schema; public bool allowed; public string checkedAt; public string reason; public Check[] checks; }
    public class Status { public int schema=1; public bool allowed; public string checkedAt; public string reason; public Check[] checks; public bool monitor=true; }
    public class NetworkState { public string Status,CheckedAt,Provider; public bool FailClosed; public int FilterCount; }
    static bool ValidNetwork(NetworkState state) {
        return state!=null&&state.Status=="PASS"&&!state.FailClosed&&state.FilterCount>=8&&
            state.Provider=="b78cde91-d8e2-4630-9a98-e759d4b29548"&&Fresh(state.CheckedAt,150000);
    }
    static bool NetworkLayer(out string reason) {
        try {
            string file=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),@"ClaudeNetworkGuard\status.json");
            var state=Json.Deserialize<NetworkState>(File.ReadAllText(file));
            bool ok=ValidNetwork(state);reason=ok?"应用级网络阻断规则已核对":"网络层保护未就绪或检查已过期";return ok;
        }catch{reason="应用级网络保护未安装或状态不可读";return false;}
    }
    [DllImport("iphlpapi.dll")] static extern uint GetBestInterface(uint address, out uint index);
    static bool Network(out string reason) {
        try {
            if(Process.GetProcessesByName("FlClashCore").Length == 0) {reason="FlClash 核心未运行";return false;}
            foreach(var n in NetworkInterface.GetAllNetworkInterfaces()) {
                if(n.Name!="FlClash" || n.Description.IndexOf("Meta",StringComparison.OrdinalIgnoreCase)<0 || n.OperationalStatus!=OperationalStatus.Up)continue;
                var props=n.GetIPProperties().GetIPv4Properties();if(props==null)continue;
                foreach(string ip in new[]{"1.1.1.1","8.8.8.8"}) {uint idx;if(GetBestInterface(BitConverter.ToUInt32(IPAddress.Parse(ip).GetAddressBytes(),0),out idx)!=0||idx!=props.Index){reason="公网路由未进入 TUN";return false;}}
                return NetworkLayer(out reason);
            }
            reason="TUN 网卡未启用";return false;
        }catch{reason="无法验证本机路由";return false;}
    }
    static bool Fresh(string timestamp, int maxMs) {
        DateTime t;if(!DateTime.TryParse(timestamp,System.Globalization.CultureInfo.InvariantCulture,System.Globalization.DateTimeStyles.RoundtripKind,out t))return false;
        double age=(DateTime.UtcNow-t.ToUniversalTime()).TotalMilliseconds;return age>=0&&age<maxMs;
    }
    static Evidence ReadEvidence() {try{return Json.Deserialize<Evidence>(File.ReadAllText(Path.Combine(Data,"evidence.json")));}catch{return null;}}
    static bool Valid(Evidence e) {
        string[] ids={"policy","mode","tun","ipv6","port","node-identity","selection","group","disk-rules","live-rules","dns","exit","stable"};
        return e!=null&&e.schema==1&&e.allowed&&Fresh(e.checkedAt,12000)&&e.checks!=null&&
            e.checks.Length==ids.Length&&ids.All(id=>e.checks.Count(c=>c.id==id&&c.ok)==1);
    }
    static bool Heartbeat() {try{var s=Json.Deserialize<Status>(File.ReadAllText(Path.Combine(Data,"status.json")));return s.monitor&&s.allowed&&Fresh(s.checkedAt,3000);}catch{return false;}}
    static void SetGate() {
        using(var root=RegistryKey.OpenBaseKey(RegistryHive.LocalMachine,RegistryView.Registry64))
        using(var k=root.CreateSubKey(Key)) {
            string old=k.GetValue("Debugger") as string;
            if(!String.IsNullOrEmpty(old)&&old!=Blocker)throw new InvalidOperationException("Foreign IFEO owner");
            k.SetValue("Debugger",Blocker,RegistryValueKind.String);
            k.SetValue("ShuniangGuardOwner","v1",RegistryValueKind.String);
        }
    }
    static bool GateInstalled() {try{using(var root=RegistryKey.OpenBaseKey(RegistryHive.LocalMachine,RegistryView.Registry64))using(var k=root.OpenSubKey(Key)){return k!=null&&(string)k.GetValue("Debugger")==Blocker;}}catch{return false;}}
    static void Atomic(string file, string text) {
        string temp=file+".new";File.WriteAllText(temp,text,Encoding.UTF8);
        if(File.Exists(file))File.Replace(temp,file,null);else File.Move(temp,file);
    }
    static void Log(string message) {try{string p=Path.Combine(Data,"guard.log");if(File.Exists(p)&&new FileInfo(p).Length>1048576)File.Move(p,p+"."+DateTime.UtcNow.Ticks);File.AppendAllText(p,DateTime.UtcNow.ToString("o")+" "+message+Environment.NewLine);}catch{}}
    static bool IsClaude(string file) {
        if(!String.Equals(Path.GetFileName(file),"Claude.exe",StringComparison.OrdinalIgnoreCase))return false;
        // Package files must reside in WindowsApps; normal-user writable paths are not accepted.
        string full=Path.GetFullPath(file);
        return full.IndexOf(@"\WindowsApps\Claude_",StringComparison.OrdinalIgnoreCase)>0 && File.Exists(full);
    }
    static void StopClaude() {
        foreach(var p in Process.GetProcessesByName("Claude")) using(p)try{
            if(IsClaude(p.MainModule.FileName)){p.Kill();Log("Stopped protected package process pid="+p.Id);}
        }catch(Exception e){Log("Stop unavailable "+e.GetType().Name);}
    }
    static Process StartSensor() {
        return Process.Start(new ProcessStartInfo(Path.Combine(Root,"node.exe"),Quote(Path.Combine(Root,"sensor.cjs"))+" --policy "+Quote(Path.Combine(Data,"policy.json"))+" --output "+Quote(Path.Combine(Data,"evidence.json"))) {UseShellExecute=false,CreateNoWindow=true});
    }
    static int Monitor() {
        bool created;using(var mutex=new Mutex(true,@"Global\ShuniangGuardMonitor",out created)) {
            if(!created)return 0;Process sensor=null;string prior=null;DateTime? stable=null;
            try {
                SetGate();sensor=StartSensor();
                while(true) {
                    if(sensor.HasExited){sensor.Dispose();sensor=StartSensor();}
                    SetGate();string reason;bool local=Network(out reason);var e=ReadEvidence();bool allow=local&&Valid(e);
                    if(!allow){stable=null;if(local)reason=e==null?"等待节点与分流检查":!Fresh(e.checkedAt,12000)?"节点与分流检查已过期，启动保持锁定":e.reason??"检查失败";StopClaude();}
                    else {if(stable==null)stable=DateTime.UtcNow;if((DateTime.UtcNow-stable.Value).TotalSeconds<2){allow=false;reason="等待检查连续稳定 2 秒";}else reason="节点、分流与出口检查通过";}
                    string networkReason;bool networkOk=NetworkLayer(out networkReason);
                    var checks=(e==null||e.checks==null?new Check[0]:e.checks).Concat(new[]{new Check{id="network-layer",ok=networkOk,message=networkReason}}).ToArray();
                    Atomic(Path.Combine(Data,"status.json"),Json.Serialize(new Status{allowed=allow,checkedAt=DateTime.UtcNow.ToString("o"),reason=reason,checks=checks}));
                    if(reason!=prior){Log((allow?"ALLOW ":"BLOCK ")+reason);prior=reason;}
                    Thread.Sleep(250);
                }
            }catch(Exception e){Log("Monitor failed "+e.GetType().Name);return 1;}
            finally{if(sensor!=null){try{if(!sensor.HasExited)sensor.Kill();}catch{}sensor.Dispose();}try{Atomic(Path.Combine(Data,"status.json"),Json.Serialize(new Status{allowed=false,checkedAt=DateTime.UtcNow.ToString("o"),reason="保护后台未运行"}));}catch{}}
        }
    }
    static bool CheckNow(out string reason) {
        if(!GateInstalled()||!Heartbeat()){reason="后台未就绪、检查失败或心跳过期";return false;}
        if(!Network(out reason))return false;
        try {
            var start=new ProcessStartInfo(Path.Combine(Root,"node.exe"),Quote(Path.Combine(Root,"sensor.cjs"))+" --once --policy "+Quote(Path.Combine(Data,"policy.json"))) {UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true};
            using(var p=Process.Start(start)) {
                var task=p.StandardOutput.ReadToEndAsync();
                if(!p.WaitForExit(10000)){p.Kill();reason="启动前检查超时";return false;}
                var e=Json.Deserialize<Evidence>(task.GetAwaiter().GetResult());
                if(p.ExitCode!=0||!Valid(e)){reason=e==null?"启动前检查失败":e.reason;return false;}
            }
            return Heartbeat()&&Network(out reason);
        }catch{reason="无法完成启动前检查";return false;}
    }
    static int Block(string reason) {MessageBox.Show("Claude 启动已锁定。\n\n"+reason+"\n\n请从书娘的保护面板查看检查项。", "书娘守护",MessageBoxButtons.OK,MessageBoxIcon.Information);return 3;}
    public static string Quote(string text) {
        if(text==null)return "\"\"";var b=new StringBuilder("\"");int slash=0;
        foreach(char c in text){if(c=='\\'){slash++;continue;}if(c=='\"'){b.Append('\\',slash*2+1).Append(c);}else{b.Append('\\',slash).Append(c);}slash=0;}
        return b.Append('\\',slash*2).Append('"').ToString();
    }
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct STARTUPINFO {public uint cb;public string reserved,desktop,title;public uint x,y,xs,ys,xc,yc,fill,flags;public ushort show,reserved2;public IntPtr reservedPtr,input,output,error;}
    [StructLayout(LayoutKind.Sequential)] struct PI {public IntPtr process,thread;public uint pid,tid;}
    [StructLayout(LayoutKind.Explicit,Size=176)] struct DEBUG_EVENT { [FieldOffset(0)]public uint code;[FieldOffset(4)]public uint pid;[FieldOffset(8)]public uint tid;[FieldOffset(16)]public uint exception;[FieldOffset(16)]public IntPtr file;[FieldOffset(24)]public IntPtr process;[FieldOffset(32)]public IntPtr thread; }
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool CreateProcess(string app,StringBuilder cmd,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr env,string cwd,ref STARTUPINFO si,out PI pi);
    [DllImport("kernel32.dll",SetLastError=true)]static extern bool WaitForDebugEvent(out DEBUG_EVENT e,uint ms);
    [DllImport("kernel32.dll")]static extern bool ContinueDebugEvent(uint pid,uint tid,uint status);
    [DllImport("kernel32.dll")]static extern bool DebugActiveProcessStop(uint pid);
    [DllImport("kernel32.dll")]static extern bool DebugSetProcessKillOnExit(bool kill);
    [DllImport("kernel32.dll")]static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")]static extern bool TerminateProcess(IntPtr handle,uint code);
    static int DebugLaunch(string file,string[] args) {
        var si=new STARTUPINFO();si.cb=(uint)Marshal.SizeOf(si);PI pi;
        var command=new StringBuilder(Quote(file)+(args.Length==0?"":" "+String.Join(" ",args.Select(Quote))));
        // DEBUG_ONLY_THIS_PROCESS bypasses recursive IFEO invocation. Detach at the initial breakpoint.
        if(!CreateProcess(file,command,IntPtr.Zero,IntPtr.Zero,false,2,IntPtr.Zero,Path.GetDirectoryName(file),ref si,out pi))return 20;
        bool detached=false;try {
            DebugSetProcessKillOnExit(true);var deadline=DateTime.UtcNow.AddSeconds(10);
            while(DateTime.UtcNow<deadline) {
                DEBUG_EVENT e;if(!WaitForDebugEvent(out e,1000))continue;
                if(e.code==3&&e.file!=IntPtr.Zero)CloseHandle(e.file);
                if(e.code==6&&e.file!=IntPtr.Zero)CloseHandle(e.file);
                bool initial=e.code==1&&e.exception==0x80000003;
                ContinueDebugEvent(e.pid,e.tid,e.code==1&&!initial?0x80010001u:0x00010002u);
                if(initial){detached=DebugActiveProcessStop(pi.pid);return detached?0:21;}
                if(e.code==5)return 0;
            }
            return 22;
        }finally{if(!detached)TerminateProcess(pi.process,23);CloseHandle(pi.thread);CloseHandle(pi.process);}
    }
    [STAThread]static int Main(string[] args) {
        Application.EnableVisualStyles();if(args.Length==0)return Block("请从书娘保护面板使用明确的启动入口");
        string mode=args[0];
        if(mode=="--monitor")return Monitor();
#if TEST_PROBE
        if(mode=="--probe-block")return 3;
        // Test-only path can ONLY run the harmless build-time fixture, never a Claude image.
        if(mode=="--probe-allow" && args.Length>=2 && String.Equals(Path.GetFullPath(args[1]),Path.Combine(Root,"ShuniangGuardProbe.exe"),StringComparison.OrdinalIgnoreCase))return DebugLaunch(args[1],new string[0]);
#endif
        if(mode=="--self-test") {
            if(Fresh(DateTime.UtcNow.AddSeconds(60).ToString("o"),12000)||Fresh("broken",12000)||Valid(null))return 10;
            var net=new NetworkState{Status="PASS",CheckedAt=DateTime.UtcNow.ToString("o"),Provider="b78cde91-d8e2-4630-9a98-e759d4b29548",FilterCount=8};
            if(!ValidNetwork(net)||ValidNetwork(null))return 11;
            net.FailClosed=true;if(ValidNetwork(net))return 12;net.FailClosed=false;
            net.CheckedAt=DateTime.UtcNow.AddMinutes(-3).ToString("o");if(ValidNetwork(net))return 13;
            net.CheckedAt=DateTime.UtcNow.ToString("o");net.FilterCount=0;if(ValidNetwork(net))return 14;
            net.FilterCount=8;net.Provider="wrong-owner";if(ValidNetwork(net))return 15;
            Console.WriteLine("PASS no target launched");return 0;
        }
        if(mode!="--intercept" && mode!="--launch")return 4;
        string reason;if(!CheckNow(out reason))return Block(reason);
        if(mode=="--launch") {
            // User-only explicit action; actual Claude.exe is still intercepted and checked again.
            Process.Start(new ProcessStartInfo("explorer.exe",@"shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude"){UseShellExecute=true});return 0;
        }
        if(args.Length<2||!IsClaude(args[1]))return Block("目标不是受保护的 Claude 安装包");
        return DebugLaunch(args[1],args.Skip(2).ToArray());
    }
}
