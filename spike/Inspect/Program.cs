// =====================================================================
//  Inspect (spike)  -  load-only inspector for NordVPN's .NET assemblies.
//  分析工具:用 MetadataLoadContext「只加载、不执行」地检查 NordVPN 的 .NET 程序集。
//
//  Modes / 两种模式:
//    dotnet run -c Release         -> dump the gRPC/IPC contract + auth layer
//                                     导出 gRPC/IPC 契约与认证层
//    dotnet run -c Release -- cli  -> extract the built-in CLI grammar
//                                     提取内置 CLI 的命令/参数语法
//  It NEVER runs NordVPN code (MetadataLoadContext = reflection only).
//  绝不执行 NordVPN 的代码(MetadataLoadContext = 仅反射)。
//  Educational / research artifact only. / 仅供学习与研究。
// =====================================================================
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;

namespace Inspect
{
    internal static class Program
    {
        // App install dir - change to your installed version. / 客户端安装目录——改成你装的版本。
        const string NordDir = @"C:\Program Files\NordVPN\8.4.3.0";
        static readonly string[] Fw =
        {
            @"C:\Program Files\dotnet\shared\Microsoft.NETCore.App\8.0.23",
            @"C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App\8.0.23",
            @"C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App\8.0.23",
        };
        static MetadataLoadContext _mlc;
        static readonly HashSet<string> _seen = new HashSet<string>();

        static void Main(string[] argv)
        {
            var byName = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var p in Directory.GetFiles(NordDir, "*.dll")) byName[Path.GetFileName(p)] = p;
            foreach (var fw in Fw) if (Directory.Exists(fw))
                foreach (var p in Directory.GetFiles(fw, "*.dll")) if (!byName.ContainsKey(Path.GetFileName(p))) byName[Path.GetFileName(p)] = p;

            _mlc = new MetadataLoadContext(new PathAssemblyResolver(byName.Values), "System.Private.CoreLib");

            if (argv.Length > 0 && argv[0] == "cli") { DumpCli(); return; }

            Section("1) CONNECTION CONTRACT INTERFACES (*Grpc with Connect/Disconnect)");
            var contractAsms = new[] { "NordSecurity.NordVpn.LegacyConnection.Contracts", "NordSecurity.NordVpn.Connection.Contracts", "NordVpn.ServiceProxy", "NordVpn.Service.Contracts" };
            var msgTypes = new List<Type>();
            foreach (var an in contractAsms)
            {
                var asm = TryLoad(an);
                if (asm == null) continue;
                foreach (var t in SafeTypes(asm).Where(t => t.IsInterface && t.Name.EndsWith("Grpc")))
                {
                    var methods = SafeMethods(t);
                    if (!methods.Any(m => m.Name.StartsWith("Connect") || m.Name.StartsWith("Disconnect") || m.Name.Contains("Connection"))) continue;
                    DumpInterface(t, msgTypes);
                }
            }

            Section("2) MESSAGE / DTO TYPES referenced by those methods (is it protobuf?)");
            foreach (var t in msgTypes.Distinct().Where(t => t != null))
                DumpMessage(t, 0);

            Section("3) IPC ANNOTATION ATTRIBUTES (how a C# method maps to a wire operation)");
            var ann = TryLoad("NordSecurity.Communication.Ipc.Annotations");
            if (ann != null)
                foreach (var t in SafeTypes(ann).Where(t => t.Name.EndsWith("Attribute")))
                {
                    Console.WriteLine($"  [attr type] {t.FullName}");
                    foreach (var c in t.GetConstructors())
                        Console.WriteLine($"       ctor(" + string.Join(", ", c.GetParameters().Select(p => $"{Short(p.ParameterType)} {p.Name}")) + ")");
                    foreach (var p in t.GetProperties(BindingFlags.Public | BindingFlags.Instance))
                        Console.WriteLine($"       prop {Short(p.PropertyType)} {p.Name}");
                }

            Section("4) IPC / PIPE / AUTH FRAMEWORK (channel creation, pipe naming, auth/handshake)");
            var fwAsms = new[] { "NordSecurity.Communication.Ipc.Core", "NordSecurity.Grpc.NamedPipes", "NordSecurity.Communication.Pipes", "NordSecurity.Communication.InProcess" };
            var rx = new System.Text.RegularExpressions.Regex("Auth|Token|Identity|Handshake|Security|Credential|Broker|Session|PipeName|Endpoint|Address|Channel|Operation|Dispatcher|Method|Marshal|Serial", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            foreach (var an in fwAsms)
            {
                var asm = TryLoad(an);
                if (asm == null) { Console.WriteLine($"  ({an} not loaded)"); continue; }
                Console.WriteLine($"  === {an} ===");
                foreach (var t in SafeTypes(asm).Where(t => rx.IsMatch(t.Name)).OrderBy(t => t.Name))
                {
                    Console.WriteLine($"    {Kind(t)} {t.FullName}");
                    foreach (var m in t.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly).Take(8))
                        Console.WriteLine($"        {Short(m.ReturnType)} {m.Name}(" + string.Join(", ", m.GetParameters().Select(p => Short(p.ParameterType))) + ")");
                    foreach (var f in t.GetFields(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance).Where(f => f.IsLiteral || f.FieldType == typeof(string)).Take(6))
                    {
                        object v = null; try { v = f.GetRawConstantValue(); } catch { }
                        Console.WriteLine($"        field {Short(f.FieldType)} {f.Name}" + (v != null ? $" = \"{v}\"" : ""));
                    }
                }
            }

            Section("5) STRING CONSTANTS in pipe/grpc layer (pipe-name templates, service ids)");
            // handled separately via strings; here just list literal string fields found above.
            Console.WriteLine("  (see field dumps above)");
        }

        static void DumpInterface(Type t, List<Type> msgs)
        {
            Console.WriteLine($"\n  INTERFACE {t.FullName}");
            foreach (var a in t.GetCustomAttributesData()) Console.WriteLine($"     [iface-attr] {FormatAttr(a)}");
            foreach (var m in SafeMethods(t))
            {
                Console.WriteLine($"     {Short(m.ReturnType)} {m.Name}(" + string.Join(", ", m.GetParameters().Select(p => $"{Short(p.ParameterType)} {p.Name}")) + ")");
                foreach (var a in m.GetCustomAttributesData()) Console.WriteLine($"         [m-attr] {FormatAttr(a)}");
                foreach (var p in m.GetParameters()) Collect(p.ParameterType, msgs);
                Collect(Unwrap(m.ReturnType), msgs);
            }
        }

        static void DumpMessage(Type t, int depth)
        {
            if (t == null || depth > 2) return;
            var key = t.FullName ?? t.Name;
            if (!_seen.Add(key)) return;
            if (IsSimple(t)) return;

            bool isProto = t.GetInterfaces().Any(i => (i.FullName ?? "").StartsWith("Google.Protobuf.IMessage"));
            if (t.IsEnum)
            {
                Console.WriteLine($"\n  ENUM {t.FullName}");
                foreach (var f in t.GetFields(BindingFlags.Public | BindingFlags.Static))
                { object v = null; try { v = f.GetRawConstantValue(); } catch { } Console.WriteLine($"       {f.Name} = {v}"); }
                return;
            }
            Console.WriteLine($"\n  {(isProto ? "PROTOBUF-MSG" : "DTO")} {t.FullName}");
            foreach (var a in t.GetCustomAttributesData()) Console.WriteLine($"       [type-attr] {FormatAttr(a)}");
            foreach (var p in t.GetProperties(BindingFlags.Public | BindingFlags.Instance))
            {
                Console.WriteLine($"       {Short(p.PropertyType)} {p.Name}");
                Collect(p.PropertyType, null, depth + 1);
            }
        }

        static readonly List<(Type, int)> _pending = new List<(Type, int)>();
        static void Collect(Type t, List<Type> msgs, int depth = 0)
        {
            t = Unwrap(t);
            if (t == null || IsSimple(t)) return;
            if (t.IsArray) { Collect(t.GetElementType(), msgs, depth); return; }
            if (t.IsGenericType) { foreach (var g in t.GetGenericArguments()) Collect(g, msgs, depth); }
            if ((t.Namespace ?? "").StartsWith("System")) return;
            if (msgs != null && !msgs.Contains(t)) msgs.Add(t);
            if (msgs == null) DumpMessage(t, depth);
        }

        // ---- helpers / 辅助方法 ----
        static Assembly TryLoad(string simpleName)
        {
            try { return _mlc.LoadFromAssemblyPath(Path.Combine(NordDir, simpleName + ".dll")); }
            catch (Exception e) { Console.WriteLine($"  (load fail {simpleName}: {e.GetType().Name})"); return null; }
        }
        static IEnumerable<Type> SafeTypes(Assembly a) { try { return a.GetTypes(); } catch (ReflectionTypeLoadException e) { return e.Types.Where(t => t != null); } }
        static MethodInfo[] SafeMethods(Type t) { try { return t.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly); } catch { return new MethodInfo[0]; } }
        static Type Unwrap(Type t)
        {
            if (t == null) return null;
            if (t.IsGenericType)
            {
                var d = t.GetGenericTypeDefinition().Name;
                if (d.StartsWith("Task") || d.StartsWith("ValueTask") || d.StartsWith("IAsyncEnumerable") || d.StartsWith("Nullable"))
                    return Unwrap(t.GetGenericArguments()[0]);
            }
            return t;
        }
        static bool IsSimple(Type t)
        {
            if (t == null) return true;
            if (t.IsPrimitive || t.IsEnum) return t.IsPrimitive;
            var n = t.FullName ?? "";
            return n == "System.String" || n == "System.Void" || n == "System.Object" || n == "System.Guid" ||
                   n == "System.DateTime" || n == "System.TimeSpan" || n == "System.Threading.CancellationToken" || n == "System.Boolean";
        }
        static string Short(Type t)
        {
            if (t == null) return "?";
            if (t.IsGenericType)
                return t.Name.Split('`')[0] + "<" + string.Join(",", t.GetGenericArguments().Select(Short)) + ">";
            return t.Name;
        }
        static string Kind(Type t) => t.IsInterface ? "interface" : t.IsEnum ? "enum" : t.IsAbstract && t.IsSealed ? "static" : t.IsClass ? "class" : "struct";
        static string FormatAttr(CustomAttributeData a)
        {
            var args = a.ConstructorArguments.Select(x => x.Value is string s ? $"\"{s}\"" : (x.Value?.ToString() ?? "null"));
            var named = a.NamedArguments?.Select(n => $"{n.MemberName}={(n.TypedValue.Value is string s ? $"\"{s}\"" : n.TypedValue.Value)}") ?? Enumerable.Empty<string>();
            return a.AttributeType.Name + "(" + string.Join(", ", args.Concat(named)) + ")";
        }
        static void Section(string s) => Console.WriteLine($"\n========== {s} ==========");

        // ---- CLI grammar extraction (CommandLineParser attributes) / 提取 CLI 语法（读 CommandLineParser 特性） ----
        static void DumpCli()
        {
            Console.WriteLine("NORDVPN BUILT-IN CLI — complete verb/option surface (read from CommandLineParser attributes)");

            Console.WriteLine("\n=== [Verb] command classes (across all Nord* assemblies) ===");
            foreach (var file in Directory.GetFiles(NordDir, "Nord*.dll"))
            {
                Assembly asm; try { asm = _mlc.LoadFromAssemblyPath(file); } catch { continue; }
                foreach (var t in SafeTypes(asm))
                {
                    CustomAttributeData verb = null;
                    try { verb = t.GetCustomAttributesData().FirstOrDefault(a => a.AttributeType.FullName == "CommandLine.VerbAttribute"); } catch { continue; }
                    if (verb != null) DumpArgType(t, verb, Path.GetFileNameWithoutExtension(file));
                }
            }

            Console.WriteLine("\n=== option-container classes (root launch args: connect/disconnect/version + flags) ===");
            foreach (var file in Directory.GetFiles(NordDir, "NordVPNApp.dll").Concat(Directory.GetFiles(NordDir, "NordVpn.*.dll")))
            {
                Assembly asm; try { asm = _mlc.LoadFromAssemblyPath(file); } catch { continue; }
                foreach (var t in SafeTypes(asm))
                {
                    var ns = t.Namespace ?? "";
                    if (!(ns.Contains("StartupArgument") || ns.Contains("Launch") || ns.Contains("Argument") || ns.Contains("Cli") || ns.Contains("CommandLine"))) continue;
                    bool isVerb = false;
                    try { isVerb = t.GetCustomAttributesData().Any(a => a.AttributeType.FullName == "CommandLine.VerbAttribute"); } catch { }
                    if (isVerb) continue;
                    if (OptionProps(t).Count == 0) continue;
                    DumpArgType(t, null, Path.GetFileNameWithoutExtension(file));
                }
            }
        }

        static List<PropertyInfo> OptionProps(Type t)
        {
            var list = new List<PropertyInfo>();
            try {
                foreach (var p in t.GetProperties(BindingFlags.Public | BindingFlags.Instance))
                    if (p.GetCustomAttributesData().Any(a => a.AttributeType.FullName == "CommandLine.OptionAttribute" || a.AttributeType.FullName == "CommandLine.ValueAttribute"))
                        list.Add(p);
            } catch { }
            return list;
        }

        static void DumpArgType(Type t, CustomAttributeData verb, string asmName)
        {
            if (verb != null)
            {
                string vname = verb.ConstructorArguments.Count > 0 ? verb.ConstructorArguments[0].Value?.ToString() : t.Name;
                bool vdefault = verb.ConstructorArguments.Count > 1 && verb.ConstructorArguments[1].Value is bool b && b;
                Console.WriteLine($"\nVERB  {vname}{(vdefault ? "  (default)" : "")}{(NamedBool(verb, "Hidden") ? "  [HIDDEN]" : "")}   [{asmName}] {t.Name}");
                var vhelp = NamedStr(verb, "HelpText"); if (vhelp != null) Console.WriteLine($"        help: {vhelp}");
            }
            else Console.WriteLine($"\nARGS-CLASS  {t.FullName}   [{asmName}]");

            foreach (var p in t.GetProperties(BindingFlags.Public | BindingFlags.Instance))
            {
                foreach (var a in p.GetCustomAttributesData())
                {
                    var fn = a.AttributeType.FullName;
                    if (fn == "CommandLine.OptionAttribute")
                    {
                        string shortN = null, longN = null;
                        var ca = a.ConstructorArguments;
                        if (ca.Count == 1) { if (ca[0].ArgumentType.Name == "Char") shortN = ca[0].Value?.ToString(); else longN = ca[0].Value?.ToString(); }
                        else if (ca.Count >= 2) { shortN = ca[0].Value?.ToString(); longN = ca[1].Value?.ToString(); }
                        string sw = (shortN != null ? "-" + shortN : "") + (shortN != null && longN != null ? ", " : "") + (longN != null ? "--" + longN : "");
                        if (sw == "") sw = "--" + p.Name.ToLowerInvariant();
                        string meta = NamedBool(a, "Required") ? " required" : "";
                        meta += NamedBool(a, "Hidden") ? " HIDDEN" : "";
                        var def = NamedRaw(a, "Default"); if (def != null) meta += " default=" + def;
                        var setn = NamedStr(a, "SetName"); if (setn != null) meta += " set=" + setn;
                        Console.WriteLine($"        opt   {sw,-22} <{p.PropertyType.Name}>{meta}");
                        var h = NamedStr(a, "HelpText"); if (h != null) Console.WriteLine("              " + h.Replace("\r", " ").Replace("\n", "\n              "));
                    }
                    else if (fn == "CommandLine.ValueAttribute")
                    {
                        int idx = a.ConstructorArguments.Count > 0 ? Convert.ToInt32(a.ConstructorArguments[0].Value) : -1;
                        var meta = NamedStr(a, "MetaName") ?? p.Name;
                        Console.WriteLine($"        arg[{idx}] {meta} <{p.PropertyType.Name}>{(NamedBool(a, "Required") ? " required" : "")}");
                        var h = NamedStr(a, "HelpText"); if (h != null) Console.WriteLine("              " + h.Replace("\r", " ").Replace("\n", "\n              "));
                    }
                }
            }
        }
        static string NamedStr(CustomAttributeData a, string name)
        { foreach (var n in a.NamedArguments) if (n.MemberName == name && n.TypedValue.Value is string s) return s; return null; }
        static bool NamedBool(CustomAttributeData a, string name)
        { foreach (var n in a.NamedArguments) if (n.MemberName == name && n.TypedValue.Value is bool x) return x; return false; }
        static string NamedRaw(CustomAttributeData a, string name)
        { foreach (var n in a.NamedArguments) if (n.MemberName == name && n.TypedValue.Value != null) return n.TypedValue.Value.ToString(); return null; }
    }
}
