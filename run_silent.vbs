Option Explicit
Dim objShell, fso, scriptDir, psScript, i, args, cmd
Dim tempDir, batchDir, jobId, markerPath, markerFile

Set objShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = fso.BuildPath(scriptDir, "convert.ps1")

tempDir = fso.GetSpecialFolder(2) ' 2 = TemporaryFolder
batchDir = fso.BuildPath(tempDir, "WebPConverter_Batch")
If Not fso.FolderExists(batchDir) Then
    On Error Resume Next
    fso.CreateFolder(batchDir)
    On Error GoTo 0
End If

jobId = fso.GetTempName()
markerPath = fso.BuildPath(batchDir, jobId & ".pending")
On Error Resume Next
Set markerFile = fso.CreateTextFile(markerPath, True)
If WScript.Arguments.Count > 0 Then
    markerFile.WriteLine(WScript.Arguments(0))
End If
markerFile.Close
On Error GoTo 0

args = " -JobId """ & jobId & """"
For i = 0 To WScript.Arguments.Count - 1
    args = args & " """ & Replace(WScript.Arguments(i), """", """""") & """"
Next

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psScript & """" & args

objShell.Run cmd, 0, False
