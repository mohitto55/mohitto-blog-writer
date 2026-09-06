# GitHub Actions 에 등록할 Android 서명 secret 값을 출력한다.
#   Settings → Secrets and variables → Actions → New repository secret
# 실행: powershell -File tool/print_android_secrets.ps1
$root = Split-Path -Parent $PSScriptRoot
$ks = Join-Path $root 'android\app\upload-keystore.jks'
$props = Join-Path $root 'android\key.properties'
if (-not (Test-Path $ks) -or -not (Test-Path $props)) {
  Write-Error "keystore 또는 key.properties 가 없습니다: $ks / $props"
  exit 1
}
$kv = @{}
Get-Content $props | ForEach-Object { if ($_ -match '^(\w+)=(.*)$') { $kv[$matches[1]] = $matches[2] } }

Write-Output "ANDROID_KEYSTORE_BASE64="
Write-Output ([Convert]::ToBase64String([IO.File]::ReadAllBytes($ks)))
Write-Output ""
Write-Output "ANDROID_KEYSTORE_PASSWORD=$($kv['storePassword'])"
Write-Output "ANDROID_KEY_PASSWORD=$($kv['keyPassword'])"
Write-Output "ANDROID_KEY_ALIAS=$($kv['keyAlias'])"
Write-Output ""
Write-Output "keystore 파일과 key.properties 는 절대 저장소에 올리지 마세요 (.gitignore 에 포함됨). 잃어버리면 기존 설치 위에 업데이트할 수 없습니다."
