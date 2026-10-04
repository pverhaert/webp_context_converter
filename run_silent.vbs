Option Explicit
Dim objShell, fso, scriptDir, psScript, i, args, cmd

Set objShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = fso.BuildPath(scriptDir, "convert.ps1")

args = ""
For i = 0 To WScript.Arguments.Count - 1
    args = args & " """ & Replace(WScript.Arguments(i), """", """""") & """"
Next

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psScript & """" & args

objShell.Run cmd, 0, False
