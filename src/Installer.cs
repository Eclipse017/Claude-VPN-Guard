using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Web.Script.Serialization;
using Microsoft.Win32;

// The unsigned setup contains the exact public ZIP. No download, client launch, VPN change or reboot.
internal static class Installer {
 const string Version="0.2.0-preview.1", Owner="ShuniangGuard-app-v2";
 static string Here=AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
 static JavaScriptSerializer Json=new JavaScriptSerializer {MaxJsonLength=16777216};
 static string Quote(string s){return "\""+s.Replace("\"","\\\"")+"\"";}
 static string Under(string root,string relative){
  string full=Path.GetFullPath(Path.Combine(root,relative));
  if(!full.StartsWith(Path.GetFullPath(root).TrimEnd('\\')+"\\",StringComparison.OrdinalIgnoreCase))throw new Exception("安装路径越界");
  return full;
 }
 static void CheckTree(string root){
  for(var p=new DirectoryInfo(root);p!=null;p=p.Parent)if(p.Exists&&(p.Attributes&FileAttributes.ReparsePoint)!=0)throw new Exception("安装路径不能包含链接目录");
 }
 static void Start(string exe,string args){Process.Start(new ProcessStartInfo(exe,args){UseShellExecute=false,CreateNoWindow=true,WorkingDirectory=Path.GetDirectoryName(exe)});}
 static int Elevated(string root,string script,string args){
  var p=Process.Start(new ProcessStartInfo(Under(root,"pwsh\\pwsh.exe"),"-NoLogo -NoProfile -ExecutionPolicy Bypass -File "+Quote(Under(root,"app\\scripts\\"+script))+" "+args){UseShellExecute=true,Verb="runas",WindowStyle=ProcessWindowStyle.Hidden});p.WaitForExit();return p.ExitCode;
 }
 static void Shortcut(string root,string file,bool wizard){
  dynamic ws=Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));dynamic link=ws.CreateShortcut(file);
  link.TargetPath=Under(root,"runtime\\electron.exe");link.Arguments=Quote(Under(root,"app\\src\\main.cjs"))+(wizard?" --setup":"");link.WorkingDirectory=root;link.Description="书娘守护：关闭桌宠后后台保护继续";link.Save();
 }
 static void DeleteOwnedShortcut(string file,string root){
  if(!File.Exists(file))return;dynamic ws=Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));dynamic link=ws.CreateShortcut(file);
  if(String.Equals((string)link.TargetPath,Under(root,"runtime\\electron.exe"),StringComparison.OrdinalIgnoreCase))File.Delete(file);
 }
 static string Hash(string file){using(var s=File.OpenRead(file))using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(s)).Replace("-","");}
 static List<Dictionary<string,object>> Manifest(string root){return Json.Deserialize<List<Dictionary<string,object>>>(File.ReadAllText(Under(root,"manifest.json")));}
 static void Install(string target,bool fixture,bool shortcut){
  target=Path.GetFullPath(target);CheckTree(target);if(Directory.Exists(target))throw new Exception("目标目录已存在。为保留旧文件，请先卸载该版本或使用新版本安装包。");
  string finalTarget=target;target=target+".installing-"+Guid.NewGuid();
  Directory.CreateDirectory(target);
  try {
   using(var input=Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip")){
    if(input==null)throw new Exception("安装载荷缺失，请下载完整 Setup.exe");
    using(var zip=new ZipArchive(input,ZipArchiveMode.Read)){
     var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
     foreach(var entry in zip.Entries){
      string name=entry.FullName.Replace('\\','/');int slash=name.IndexOf('/');if(slash<0)throw new Exception("安装载荷结构错误");string relative=name.Substring(slash+1);if(relative.Length==0)continue;
      string dest=Under(target,relative.Replace('/','\\'));if(!seen.Add(dest))throw new Exception("安装载荷包含重复路径");
      if(name.EndsWith("/")){Directory.CreateDirectory(dest);continue;}
      Directory.CreateDirectory(Path.GetDirectoryName(dest));using(var source=entry.Open())using(var output=new FileStream(dest,FileMode.CreateNew))source.CopyTo(output);
     }
    }
   }
   var manifest=Manifest(target);foreach(var e in manifest){string f=Under(target,(string)e["path"]);if(!File.Exists(f)||!Hash(f).Equals((string)e["sha256"],StringComparison.OrdinalIgnoreCase))throw new Exception("文件校验失败："+e["path"]);}
   File.WriteAllText(Under(target,"installation.json"),Json.Serialize(new {owner=Owner,version=Version,fixture=fixture,files=manifest.Count}));
   Directory.Move(target,finalTarget);target=finalTarget;
   if(!fixture){
    string menu=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),"书娘守护.lnk");Shortcut(target,menu,true);
    if(shortcut)Shortcut(target,Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),"书娘守护.lnk"),false);
    using(var key=Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\ShuniangGuard-"+Version)){
     key.SetValue("DisplayName","书娘守护 "+Version);key.SetValue("DisplayVersion",Version);key.SetValue("Publisher","ShuniangGuard Community");key.SetValue("InstallLocation",target);key.SetValue("UninstallString",Quote(Under(target,"ShuniangSetupHost.exe"))+" --uninstall");key.SetValue("NoModify",1);key.SetValue("NoRepair",1);
    }
   }
  }catch{File.WriteAllText(Under(target,"install-failed.txt"),"安装未完成，请保留此目录排查；保护尚未启用。");throw;}
 }
 static void RemoveFiles(string target,bool fixture){
  target=Path.GetFullPath(target);CheckTree(target);
  var marker=Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(Under(target,"installation.json")));
  if((string)marker["owner"]!=Owner||(bool)marker["fixture"]!=fixture)throw new Exception("安装归属不符，未移除文件");
  // Verify all removal targets before removing any file. Never recursively delete unknown content.
  var files=new List<string>();foreach(var e in Manifest(target)){string f=Under(target,(string)e["path"]);CheckTree(Path.GetDirectoryName(f));if(File.Exists(f)&&(File.GetAttributes(f)&FileAttributes.ReparsePoint)!=0)throw new Exception("文件是链接，拒绝卸载");files.Add(f);}
  var parents=new HashSet<string>(StringComparer.OrdinalIgnoreCase);foreach(var f in files){string d=Path.GetDirectoryName(f);while(d.Length>target.Length){parents.Add(d);d=Path.GetDirectoryName(d);}if(File.Exists(f))File.Delete(f);}
  File.Delete(Under(target,"manifest.json"));File.Delete(Under(target,"installation.json"));
  var dirs=new List<string>(parents);dirs.Sort((a,b)=>b.Length.CompareTo(a.Length));foreach(var d in dirs)if(Directory.Exists(d)&&Directory.GetFileSystemEntries(d).Length==0)Directory.Delete(d);if(Directory.GetFileSystemEntries(target).Length==0)Directory.Delete(target);
 }
 [STAThread] static int Main(string[] args){
  Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
  try {
   if(args.Length==2&&args[0]=="--fixture-install"){Install(args[1],true,false);return 0;}
   if(args.Length==2&&args[0]=="--fixture-remove"){RemoveFiles(args[1],true);return 0;}
   if(args.Length==3&&args[0]=="--elevate-install")return Elevated(Here,"Install-Standalone.ps1","-PolicyPath "+Quote(Path.GetFullPath(args[1]))+" -ResultPath "+Quote(Path.GetFullPath(args[2])));
   if(args.Length==2&&args[0]=="--remove-files"){System.Threading.Thread.Sleep(1500);RemoveFiles(args[1],false);return 0;}
   if(args.Length==1&&args[0]=="--uninstall"){
    if(MessageBox.Show("卸载本版本书娘应用及它安装的系统保护？\n其他保护程序与已有的独立网络规则会保留。\n请先退出书娘窗口；不会启动 Claude。","卸载书娘守护",MessageBoxButtons.YesNo)!=DialogResult.Yes)return 0;
    var marker=Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(Under(Here,"installation.json")));if((string)marker["owner"]!=Owner)throw new Exception("安装归属错误");
    string result=Path.Combine(Path.GetTempPath(),"shuniang-uninstall-"+Guid.NewGuid()+".json");
    if(Elevated(Here,"Uninstall-Standalone.ps1","-ResultPath "+Quote(result))!=0)throw new Exception("后台保护卸载未完成，保留应用以便重试。详见："+result);
    DeleteOwnedShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),"书娘守护.lnk"),Here);DeleteOwnedShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),"书娘守护.lnk"),Here);
    Registry.CurrentUser.DeleteSubKeyTree(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\ShuniangGuard-"+Version,false);
    string temp=Path.Combine(Path.GetTempPath(),"shuniang-remove-"+Guid.NewGuid()+".exe");File.Copy(Assembly.GetExecutingAssembly().Location,temp);Start(temp,"--remove-files "+Quote(Here));return 0;
   }
   string capture=args.Length==2&&args[0]=="--verify-dialog"?Path.GetFullPath(args[1]):null;
   if(args.Length!=0&&capture==null)throw new Exception("未知安装参数");
   using(var form=new Form {Text="安装书娘守护",ClientSize=new Size(560,330),StartPosition=FormStartPosition.CenterScreen,FormBorderStyle=FormBorderStyle.FixedDialog,MaximizeBox=false,Font=new Font("Microsoft YaHei UI",10)}){
    var title=new Label {Text="书娘守护",Font=new Font("Microsoft YaHei UI",24,FontStyle.Bold),AutoSize=true,Location=new Point(28,25)};
    var info=new Label {Text="一键安装 · 中文配置向导 · 本地互动\n\n自带运行环境，无需旧版 ClaudeVpnGuard。\n安装后选择节点并检查地区，再确认启用保护。\n启用系统保护时 Windows 会请求一次管理员权限。\n安装器不会打开 Claude。",Location=new Point(30,85),Size=new Size(505,145)};
    var desktop=new CheckBox {Text="创建桌面书娘快捷方式（可随时退出，不影响后台保护）",Checked=true,Location=new Point(30,235),AutoSize=true};
    var button=new Button {Text="安装并打开配置向导",Location=new Point(280,275),Size=new Size(240,36)};
    button.Click+=async delegate {button.Enabled=false;desktop.Enabled=false;bool makeLink=desktop.Checked;string dest=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","ShuniangGuard",Version);try{button.Text="正在安装与校验…";await System.Threading.Tasks.Task.Run(()=>Install(dest,false,makeLink));Start(Under(dest,"runtime\\electron.exe"),Quote(Under(dest,"app\\src\\main.cjs"))+" --setup");form.Close();}catch(Exception ex){MessageBox.Show(ex.Message,"安装未完成");button.Text="重试安装";button.Enabled=true;desktop.Enabled=true;}};
    form.Controls.AddRange(new Control[]{title,info,desktop,button});
    if(capture!=null){var timer=new System.Windows.Forms.Timer {Interval=700};timer.Tick+=delegate{timer.Stop();using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,new Rectangle(0,0,form.Width,form.Height));bitmap.Save(capture,System.Drawing.Imaging.ImageFormat.Png);}form.Close();};form.Shown+=delegate{timer.Start();};}
    Application.Run(form);
   }
   return 0;
  }catch(Exception ex){if(args.Length>0&&args[0].StartsWith("--fixture")){File.WriteAllText(Path.Combine(Path.GetTempPath(),"ShuniangInstaller-test-error.txt"),ex.ToString());}else MessageBox.Show(ex.Message,"书娘守护");return 1;}
 }
}
