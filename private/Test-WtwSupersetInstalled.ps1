# Define path for Superset's local database
$script:SupersetDbPath = Join-Path $HOME '.superset' 'local.db'

function Test-WtwSupersetInstalled {
    return (Test-Path $script:SupersetDbPath)
}
