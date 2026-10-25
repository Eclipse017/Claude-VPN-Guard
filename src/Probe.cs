using System;
using System.IO;
class Probe {static int Main(){File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"probe-ran.txt"),"Harmless offline probe executed.");return 0;}}
