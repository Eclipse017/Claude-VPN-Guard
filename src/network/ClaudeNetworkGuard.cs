// Windows x64, .NET Framework 4.8. WFP management only: never launches Claude.
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using System.Net.NetworkInformation;
using System.ServiceProcess;
using System.Threading;
using System.Diagnostics;

public sealed class NetworkGuardConfig {
    public int Schema;
    public string AdapterName;
    public string AdapterDescription;
    public string PackageSid;
    public string[] PackageRoots;
    public string[] TestPrograms;
    public bool TestMode;
    public bool DenyAllNonLoopback;
}

public static class ClaudeNetworkGuard {
    // This provider owns only the filters created by this component.
    static readonly Guid Provider=new Guid("b78cde91-d8e2-4630-9a98-e759d4b29548");
    static readonly Guid Sublayer=new Guid("b18e6b06-e3c7-43a3-9f06-4b1c7ea62db3");
    static readonly Guid TestProvider=new Guid("243ce30f-b896-41a1-b23d-a7e4770f3fc7");
    static readonly Guid TestSublayer=new Guid("7b36b2cb-ebcf-4cb6-a8c8-cdfc311f038b");
    static readonly Guid V4=new Guid("c38d57d1-05a7-4c33-904f-7fbceee60e82");
    static readonly Guid V6=new Guid("4a72393b-319f-44bc-84c3-ba54dcb3b6b4");
    static readonly Guid AppId=new Guid("d78e1e87-8644-4ea5-9437-d809ecefc971");
    static readonly Guid PackageId=new Guid("71bc78fa-f17c-4997-a602-6abb261f351c");
    static readonly Guid LocalInterface=new Guid("4cd62a49-59c3-4969-b7f3-bda5d32890a4");
    static readonly Guid Flags=new Guid("632ce23b-5167-435c-86d7-e903684aa80c");
    const uint NotFound=0x80320003, ProviderNotFound=0x80320005, SublayerNotFound=0x80320007;
    static JavaScriptSerializer Json=new JavaScriptSerializer {MaxJsonLength=8000000};

    [StructLayout(LayoutKind.Sequential)] public struct Display { [MarshalAs(UnmanagedType.LPWStr)]public string name; [MarshalAs(UnmanagedType.LPWStr)]public string description; }
    [StructLayout(LayoutKind.Sequential)] public struct Blob {public uint size;public IntPtr data;}
    [StructLayout(LayoutKind.Explicit,Size=16)] public struct Value {[FieldOffset(0)]public uint type;[FieldOffset(8)]public ulong scalar;[FieldOffset(8)]public IntPtr ptr;}
    [StructLayout(LayoutKind.Sequential)] public struct Condition {public Guid field;public uint match;public Value value;}
    [StructLayout(LayoutKind.Sequential)] public struct Action {public uint type;public Guid key;}
    [StructLayout(LayoutKind.Explicit,Size=16)] public struct Context {[FieldOffset(0)]public ulong raw;[FieldOffset(0)]public Guid key;}
    [StructLayout(LayoutKind.Sequential)] public struct Filter {public Guid key;public Display display;public uint flags;public IntPtr provider;public Blob data;public Guid layer;public Guid sublayer;public Value weight;public uint count;public IntPtr conditions;public Action action;public Context context;public IntPtr reserved;public ulong id;public Value effective;}
    [StructLayout(LayoutKind.Sequential)] public struct ProviderInfo {public Guid key;public Display display;public uint flags;public Blob data;[MarshalAs(UnmanagedType.LPWStr)]public string service;}
    [StructLayout(LayoutKind.Sequential)] public struct SublayerInfo {public Guid key;public Display display;public uint flags;public IntPtr provider;public Blob data;public ushort weight;}

    [DllImport("fwpuclnt.dll",CharSet=CharSet.Unicode)]static extern uint FwpmEngineOpen0(string server,uint auth,IntPtr identity,IntPtr session,out IntPtr engine);
    [DllImport("fwpuclnt.dll")]static extern uint FwpmEngineClose0(IntPtr engine);
    [DllImport("fwpuclnt.dll")]static extern uint FwpmTransactionBegin0(IntPtr engine,uint flags);
    [DllImport("fwpuclnt.dll")]static extern uint FwpmTransactionCommit0(IntPtr engine);
    [DllImport("fwpuclnt.dll")]static extern uint FwpmTransactionAbort0(IntPtr engine);
    [DllImport("fwpuclnt.dll")]static extern uint FwpmProviderAdd0(IntPtr engine,ref ProviderInfo provider,IntPtr security);
    [DllImport("fwpuclnt.dll")]static extern uint FwpmProviderGetByKey0(IntPtr engine,ref Guid key,out IntPtr provider);
    [DllImport("fwpuclnt.dll")]static extern uint FwpmProviderDeleteByKey0(IntPtr engine,ref Guid key);
    [DllImport("fwpuclnt.dll")]static extern uint FwpmSubLayerAdd0(IntPtr engine,ref SublayerInfo layer,IntPtr security);
    [DllImport("fwpuclnt.dll")]static extern uint FwpmSubLayerGetByKey0(IntPtr engine,ref Guid key,out IntPtr layer);
    [DllImport("fwpuclnt.dll")]static extern uint FwpmSubLayerDeleteByKey0(IntPtr engine,ref Guid key);
    [DllImport("fwpuclnt.dll")]static extern uint FwpmFilterAdd0(IntPtr engine,ref Filter filter,IntPtr security,out ulong id);
    [DllImport("fwpuclnt.dll")]static extern uint FwpmFilterDeleteByKey0(IntPtr engine,ref Guid key);
    [DllImport("fwpuclnt.dll")]static extern uint FwpmFilterCreateEnumHandle0(IntPtr engine,IntPtr template,out IntPtr handle);
    [DllImport("fwpuclnt.dll")]static extern uint FwpmFilterEnum0(IntPtr engine,IntPtr handle,uint requested,out IntPtr entries,out uint count);
    [DllImport("fwpuclnt.dll")]static extern uint FwpmFilterDestroyEnumHandle0(IntPtr engine,IntPtr handle);
    [DllImport("fwpuclnt.dll",CharSet=CharSet.Unicode)]static extern uint FwpmGetAppIdFromFileName0(string file,out IntPtr appId);
    [DllImport("fwpuclnt.dll")]static extern void FwpmFreeMemory0(ref IntPtr memory);
    [DllImport("iphlpapi.dll")]static extern uint ConvertInterfaceIndexToLuid(uint index,out ulong luid);
    static void Check(uint result,string op){if(result!=0)throw new InvalidOperationException(op+" failed: 0x"+result.ToString("X8"));}
    static T Read<T>(IntPtr p){return (T)Marshal.PtrToStructure(p,typeof(T));}
    sealed class Memory:IDisposable {
        List<IntPtr> ptrs=new List<IntPtr>();List<IntPtr> fwps=new List<IntPtr>();
        public IntPtr Structure<T>(T value){var p=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(T)));Marshal.StructureToPtr(value,p,false);ptrs.Add(p);return p;}
        public IntPtr Bytes(byte[] data){var p=Marshal.AllocHGlobal(data.Length);Marshal.Copy(data,0,p,data.Length);ptrs.Add(p);return p;}
        public IntPtr App(string file){IntPtr p;Check(FwpmGetAppIdFromFileName0(file,out p),"Get app identity");fwps.Add(p);return p;}
        public IntPtr Conditions(Condition[] values){int size=Marshal.SizeOf(typeof(Condition));var p=Marshal.AllocHGlobal(size*values.Length);ptrs.Add(p);for(int i=0;i<values.Length;i++)Marshal.StructureToPtr(values[i],IntPtr.Add(p,size*i),false);return p;}
        public void Dispose(){foreach(var p in ptrs)Marshal.FreeHGlobal(p);foreach(var p in fwps){var q=p;FwpmFreeMemory0(ref q);}}
    }
    public class FilterRecord {
        public string Key;public string Name;public string Layer;public string Sublayer;public uint Flags;public uint Action;public ulong Id;public string[] Conditions;
    }
    static string Describe(Condition c){
        string value="";
        if(c.value.type==4)value=Read<ulong>(c.value.ptr).ToString();
        else if(c.value.type==12){var b=Read<Blob>(c.value.ptr);byte[] a=new byte[b.size];Marshal.Copy(b.data,a,0,a.Length);value=Convert.ToBase64String(a);}
        else if(c.value.type==13)value=new SecurityIdentifier(c.value.ptr).Value;
        else value=c.value.scalar.ToString();
        return c.field+"|"+c.match+"|"+c.value.type+"|"+value;
    }
    static FilterRecord Record(Filter f){var conds=new List<string>();for(int i=0;i<f.count;i++)conds.Add(Describe(Read<Condition>(IntPtr.Add(f.conditions,i*Marshal.SizeOf(typeof(Condition))))));return new FilterRecord {Key=f.key.ToString(),Name=f.display.name,Layer=f.layer.ToString(),Sublayer=f.sublayer.ToString(),Flags=f.flags,Action=f.action.type,Id=f.id,Conditions=conds.ToArray()};}
    static List<FilterRecord> Owned(IntPtr engine,Guid provider){
        var result=new List<FilterRecord>();IntPtr enumeration;Check(FwpmFilterCreateEnumHandle0(engine,IntPtr.Zero,out enumeration),"Enumerate filters");
        try {while(true){IntPtr entries;uint count;Check(FwpmFilterEnum0(engine,enumeration,256,out entries,out count),"Read filters");try {for(int i=0;i<count;i++){Filter f=Read<Filter>(Marshal.ReadIntPtr(entries,i*IntPtr.Size));if(f.provider!=IntPtr.Zero&&Read<Guid>(f.provider)==provider)result.Add(Record(f));}}finally{FwpmFreeMemory0(ref entries);}if(count<256)break;}}finally{FwpmFilterDestroyEnumHandle0(engine,enumeration);}return result;
    }
    static Guid StableKey(string value){using(var hash=SHA256.Create()){return new Guid(hash.ComputeHash(Encoding.UTF8.GetBytes(value)).Take(16).ToArray());}}
    static Condition C(Guid field,uint match,uint type,ulong scalar,IntPtr ptr){var v=new Value{type=type,scalar=scalar};if(ptr!=IntPtr.Zero)v.ptr=ptr;return new Condition{field=field,match=match,value=v};}
    static List<Filter> Desired(NetworkGuardConfig cfg,Memory mem,out ulong luid,out string[] programs){
        if(cfg.Schema!=1)throw new InvalidDataException("Unknown schema");
        luid=ulong.MaxValue; // Missing TUN fails closed; loopback IPC and explicit local proxy stay available.
        if(!cfg.DenyAllNonLoopback){var adapters=NetworkInterface.GetAllNetworkInterfaces().Where(n=>n.Name==cfg.AdapterName&&n.Description==cfg.AdapterDescription&&n.OperationalStatus==OperationalStatus.Up).ToArray();if(adapters.Length>1)throw new InvalidDataException("Ambiguous TUN identity");if(adapters.Length==1){var p=adapters[0].GetIPProperties().GetIPv4Properties();if(p!=null)Check(ConvertInterfaceIndexToLuid((uint)p.Index,out luid),"Resolve TUN LUID");}}
        var paths=new List<string>();
        if(cfg.TestMode){if(cfg.TestPrograms==null||cfg.TestPrograms.Length==0)throw new InvalidDataException("No probe");foreach(string p in cfg.TestPrograms){string full=Path.GetFullPath(p);if(!File.Exists(full)||Path.GetFileName(full)!="ClaudeNetworkProbe.exe")throw new InvalidDataException("Test scope must be harmless ClaudeNetworkProbe.exe");paths.Add(full);}}
        else {
            if(cfg.DenyAllNonLoopback||cfg.PackageSid!="S-1-15-2-3557520199-3666692283-3112367039-3524159787-2791857073-3163583606-3692855932")throw new InvalidDataException("Unapproved production identity");
            foreach(string root in cfg.PackageRoots??new string[0]){if(root!="C:\\Program Files\\WindowsApps"&&root!="D:\\WindowsApps")throw new InvalidDataException("Unapproved package root");if(!Directory.Exists(root))continue;foreach(string dir in Directory.GetDirectories(root,"Claude_*__pzs8sxrjxfjjc")){if(!File.Exists(Path.Combine(dir,"AppxManifest.xml")))continue;paths.AddRange(Directory.GetFiles(dir,"*.exe",SearchOption.AllDirectories));}}
            if(!paths.Any(p=>Path.GetFileName(p).Equals("Claude.exe",StringComparison.OrdinalIgnoreCase)))throw new InvalidDataException("Claude package not found");
        }
        programs=paths.Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(p=>p,StringComparer.OrdinalIgnoreCase).ToArray();
        var identities=new List<Tuple<string,Condition>>();
        foreach(string path in programs)identities.Add(Tuple.Create("path:"+path.ToLowerInvariant(),C(AppId,0,12,0,mem.App(path))));
        if(!cfg.TestMode){var sid=new SecurityIdentifier(cfg.PackageSid);byte[] bytes=new byte[sid.BinaryLength];sid.GetBinaryForm(bytes,0);identities.Add(Tuple.Create("package:"+cfg.PackageSid,C(PackageId,0,13,0,mem.Bytes(bytes))));}
        Guid provider=cfg.TestMode?TestProvider:Provider,sub=cfg.TestMode?TestSublayer:Sublayer;var providerPtr=mem.Structure(provider);var luidPtr=mem.Structure(luid);var filters=new List<Filter>();
        foreach(var identity in identities)foreach(Guid layer in new[]{V4,V6})foreach(bool missing in new[]{false,true}){
            var conds=new[]{identity.Item2,C(Flags,8,3,1,IntPtr.Zero),missing?C(LocalInterface,0,0,0,IntPtr.Zero):C(LocalInterface,10,4,0,luidPtr)};
            string name="ClaudeNetworkGuard "+(cfg.TestMode?"TEST ":"")+(layer==V4?"IPv4 ":"IPv6 ")+(missing?"unknown-interface ":"outside-TUN ")+identity.Item1;
            filters.Add(new Filter{key=StableKey(provider+"|"+layer+"|"+missing+"|"+identity.Item1),display=new Display{name=name,description="Block non-loopback connections outside the approved FlClash TUN. No permit rules."},flags=1,provider=providerPtr,layer=layer,sublayer=sub,weight=new Value{type=1,scalar=15},count=(uint)conds.Length,conditions=mem.Conditions(conds),action=new Action{type=0x1001}});
        }
        return filters;
    }
    static void EnsureOwner(IntPtr engine,Guid provider,Guid sub,Memory mem){
        IntPtr p;uint status=FwpmProviderGetByKey0(engine,ref provider,out p);
        string service=provider==Provider?"ClaudeNetworkGuard":null;
        if(status==ProviderNotFound){var info=new ProviderInfo{key=provider,display=new Display{name="ClaudeNetworkGuard",description="VPN_GUARD application-scoped network protection"},flags=1,service=service};Check(FwpmProviderAdd0(engine,ref info,IntPtr.Zero),"Add provider");}
        else {Check(status,"Read provider");try{var info=Read<ProviderInfo>(p);if(info.display.name!="ClaudeNetworkGuard"||info.flags!=1||info.service!=service)throw new InvalidDataException("Foreign provider ownership or service association");}finally{FwpmFreeMemory0(ref p);}}
        status=FwpmSubLayerGetByKey0(engine,ref sub,out p);
        if(status==SublayerNotFound){var info=new SublayerInfo{key=sub,display=new Display{name="ClaudeNetworkGuard",description="Application-only blocking; existing firewall rules unchanged"},flags=1,provider=mem.Structure(provider),weight=0xE000};Check(FwpmSubLayerAdd0(engine,ref info,IntPtr.Zero),"Add sublayer");}
        else {Check(status,"Read sublayer");try{var info=Read<SublayerInfo>(p);if(info.provider==IntPtr.Zero||Read<Guid>(info.provider)!=provider||info.display.name!="ClaudeNetworkGuard")throw new InvalidDataException("Foreign sublayer ownership");}finally{FwpmFreeMemory0(ref p);}}
    }
    // Windows may add INDEXED (0x40) on readback. All behavioral flags must still match.
    static bool Same(List<FilterRecord> current,List<Filter> desired){if(current.Count!=desired.Count)return false;foreach(var f in desired){var d=Record(f);var c=current.SingleOrDefault(x=>x.Key==d.Key);if(c==null||c.Layer!=d.Layer||c.Sublayer!=d.Sublayer||c.Action!=d.Action||(c.Flags & ~0x40u)!=d.Flags||!c.Conditions.OrderBy(x=>x,StringComparer.Ordinal).SequenceEqual(d.Conditions.OrderBy(x=>x,StringComparer.Ordinal)))return false;}return true;}
    public static object Run(string operation,NetworkGuardConfig cfg){
        if(IntPtr.Size!=8||Marshal.SizeOf(typeof(Filter))!=200||Marshal.SizeOf(typeof(Condition))!=40||Marshal.SizeOf(typeof(SublayerInfo))!=72||Marshal.SizeOf(typeof(ProviderInfo))!=64)throw new InvalidOperationException("Unsupported native layout");
        Guid provider=cfg.TestMode?TestProvider:Provider,sub=cfg.TestMode?TestSublayer:Sublayer;
        IntPtr engine;Check(FwpmEngineOpen0(null,10,IntPtr.Zero,IntPtr.Zero,out engine),"Open WFP");
        try {using(var mem=new Memory()){
            if(operation=="status")return new{Status="READ",Provider=provider,Filters=Owned(engine,provider)};
            bool transaction=false;try{
                Check(FwpmTransactionBegin0(engine,0),"Begin transaction");transaction=true;
                if(operation=="remove"){
                    var before=Owned(engine,provider);foreach(var r in before){Guid k=new Guid(r.Key);Check(FwpmFilterDeleteByKey0(engine,ref k),"Delete owned filter");}
                    uint s=FwpmSubLayerDeleteByKey0(engine,ref sub);if(s!=SublayerNotFound)Check(s,"Delete owned sublayer");s=FwpmProviderDeleteByKey0(engine,ref provider);if(s!=ProviderNotFound)Check(s,"Delete owned provider");
                    Check(FwpmTransactionCommit0(engine),"Commit removal");transaction=false;return new{Status="REMOVED",Count=before.Count,Remaining=Owned(engine,provider).Count};
                }
                if(operation!="apply")throw new ArgumentException("Unknown operation");
                ulong luid;string[] programs;var desired=Desired(cfg,mem,out luid,out programs);EnsureOwner(engine,provider,sub,mem);var current=Owned(engine,provider);bool changed=!Same(current,desired);
                if(changed){foreach(var r in current){Guid k=new Guid(r.Key);Check(FwpmFilterDeleteByKey0(engine,ref k),"Replace owned filter");}foreach(var item in desired){var f=item;ulong id;Check(FwpmFilterAdd0(engine,ref f,IntPtr.Zero,out id),"Add "+f.display.name);}}
                Check(FwpmTransactionCommit0(engine),"Commit policy");transaction=false;var after=Owned(engine,provider);if(!Same(after,desired))throw new InvalidOperationException("Readback mismatch: "+Json.Serialize(new{Expected=desired.Select(Record).ToArray(),Actual=after}));
                return new{Status="PASS",Changed=changed,Provider=provider,TunLuid=luid,FailClosed=luid==ulong.MaxValue,Programs=programs,FilterCount=after.Count,Filters=after};
            }finally{if(transaction)FwpmTransactionAbort0(engine);}
        }}finally{FwpmEngineClose0(engine);}
    }
    public static int Main(string[] args){try{if(args.Length==1&&args[0]=="--service"){ServiceBase.Run(new GuardService());return 0;}if(args.Length!=3)throw new ArgumentException("Usage: operation config.json result.json");var cfg=Json.Deserialize<NetworkGuardConfig>(File.ReadAllText(args[1]));var result=Run(args[0],cfg);File.WriteAllText(args[2],Json.Serialize(result),new UTF8Encoding(false));return 0;}catch(Exception e){if(args.Length==3)File.WriteAllText(args[2],Json.Serialize(new{Status="FAILED",Error=e.ToString()}));return 1;}}
    sealed class GuardService:ServiceBase {
        readonly ManualResetEvent stop=new ManualResetEvent(false);Thread worker;
        public GuardService(){ServiceName="ClaudeNetworkGuard";CanStop=true;AutoLog=true;}
        protected override void OnStart(string[] args){worker=new Thread(Work);worker.IsBackground=true;worker.Start();}
        protected override void OnStop(){stop.Set();if(worker!=null&&!worker.Join(15000))RequestAdditionalTime(15000);}
        void Work(){
            string root=AppDomain.CurrentDomain.BaseDirectory,data=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),"ClaudeNetworkGuard");
            do {
                try {using(var mutex=new Mutex(false,@"Global\ClaudeNetworkGuardReconcile")){
                    bool held=false;try {
                        held=mutex.WaitOne(10000);if(!held)continue;
                        object value;try {var cfg=Json.Deserialize<NetworkGuardConfig>(File.ReadAllText(Path.Combine(root,"policy.json")));if(cfg.TestMode)throw new InvalidDataException("Service must not use probe policy");value=ClaudeNetworkGuard.Run("apply",cfg);}catch(Exception e){value=new{Status="FAILED",Error=e.ToString()};}
                        var status=Json.Deserialize<Dictionary<string,object>>(Json.Serialize(value));status["CheckedAt"]=DateTime.UtcNow.ToString("o");
                        string target=Path.Combine(data,"status.json"),temp=target+".service.tmp";File.WriteAllText(temp,Json.Serialize(status),new UTF8Encoding(false));if(File.Exists(target))File.Replace(temp,target,null);else File.Move(temp,target);
                    }finally{if(held)mutex.ReleaseMutex();}
                }}catch(Exception e){try{EventLog.WriteEntry("ClaudeNetworkGuard",e.Message,EventLogEntryType.Error);}catch{}}
            }while(!stop.WaitOne(30000));
        }
    }
}
