param([string]$sas)
(Get-Content index.template.html -Raw).Replace('__SAS_TOKEN__', $sas) | Set-Content index.html