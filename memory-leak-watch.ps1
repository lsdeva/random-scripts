# Silent leak-scout: samples Private Memory, shows a countdown, prints ONLY suspects at the end.
# Edit $Procs / $Minutes / $IntervalSec / $MinGrowthMB as needed.

$Procs        = @("steamwebhelper","chrome","brave","msedge","msedgewebview2")
$Minutes      = 10          # total run time
$IntervalSec  = 10          # sampling interval
$MinGrowthMB  = 200         # print only if Private Memory grows by this many MB (or more)

$TotalSec  = [int]($Minutes * 60)
$Samples   = [int][math]::Max(2, [math]::Floor($TotalSec / $IntervalSec))
$Timeline  = @{}

$sw = [Diagnostics.Stopwatch]::StartNew()
for ($i=1; $i -le $Samples; $i++) {
  $remaining = [int]([math]::Max(0, $TotalSec - $sw.Elapsed.TotalSeconds))
  $mm = [int]($remaining / 60); $ss = $remaining % 60

  Write-Progress -Activity "Monitoring for leaks (quiet)" -Status ("Time remaining: {0:D2}:{1:D2}" -f $mm,$ss) `
    -PercentComplete ([int](100 * ($sw.Elapsed.TotalSeconds / $TotalSec)))

  Get-Process -Name $Procs -ErrorAction SilentlyContinue | ForEach-Object {
    $pm = [int]($_.PrivateMemorySize64 / 1MB)
    if (-not $Timeline.ContainsKey($_.Id)) {
      $Timeline[$_.Id] = [pscustomobject]@{
        Name     = $_.Name
        Id       = $_.Id
        StartPM  = $pm
        EndPM    = $pm
        StartT   = $sw.Elapsed.TotalSeconds
        EndT     = $sw.Elapsed.TotalSeconds
        Samples  = 1
      }
    } else {
      $t = $Timeline[$_.Id]
      $t.EndPM   = $pm
      $t.EndT    = $sw.Elapsed.TotalSeconds
      $t.Samples++
    }
  }

  if ($i -lt $Samples) { Start-Sleep -Seconds $IntervalSec }
}

Write-Progress -Activity "Monitoring for leaks (quiet)" -Completed

$results = $Timeline.Values | ForEach-Object {
  $dtMin = [math]::Max(0.01, (($_.EndT - $_.StartT) / 60))
  $delta = $_.EndPM - $_.StartPM
  [pscustomobject]@{
    Name         = $_.Name
    Id           = $_.Id
    StartPM_MB   = $_.StartPM
    EndPM_MB     = $_.EndPM
    GrowthMB     = $delta
    Rate_MB_Min  = [math]::Round(($delta / $dtMin), 1)
    Samples      = $_.Samples
  }
} | Where-Object { $_.GrowthMB -ge $MinGrowthMB } |
    Sort-Object GrowthMB -Descending

if (-not $results) {
  "No obvious leak-like growth detected (>= $MinGrowthMB MB) over ~$Minutes minutes."
} else {
  "Investigate these (Private Memory growth):"
  $results | Format-Table -AutoSize
}
