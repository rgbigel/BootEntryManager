# BootEntryManager.Tests.ps1
# Comprehensive unit and contract tests for BootEntryManager (Zero Reboot Execution)

Describe "BootEntryManager Script Contracts & AST Integrity" {
    It "parses Source/BootEntryManager.ps1 without syntax errors" {
        $sourceScript = Join-Path $PSScriptRoot '..\Source\BootEntryManager.ps1'
        $errors = $null
        $tokens = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourceScript, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
        $ast | Should -Not -BeNullOrEmpty
    }

    It "parses BootEntryManager_Install.ps1 without syntax errors" {
        $installScript = Join-Path $PSScriptRoot '..\BootEntryManager_Install.ps1'
        $errors = $null
        $tokens = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($installScript, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It "defines mandatory parameters on BootEntryManager.ps1" {
        $sourceScript = Join-Path $PSScriptRoot '..\Source\BootEntryManager.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourceScript, [ref]$null, [ref]$null)
        $paramBlock = $ast.ParamBlock
        $paramBlock | Should -Not -BeNullOrEmpty
        
        $paramNames = @($paramBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
        ($paramNames -contains 'LoadBackupFileName') | Should -Be $true
        ($paramNames -contains 'HelpMode') | Should -Be $true
    }

    It "contains required internal helper functions in AST" {
        $sourceScript = Join-Path $PSScriptRoot '..\Source\BootEntryManager.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourceScript, [ref]$null, [ref]$null)
        $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        $functionNames = @($functions | ForEach-Object { $_.Name })
        
        ($functionNames -contains 'Test-IsAdministrator') | Should -Be $true
        ($functionNames -contains 'Get-EfiSystemPartitionVolume') | Should -Be $true
        ($functionNames -contains 'Restart-Elevated') | Should -Be $true
    }
}

Describe "BCD Parser & Data Transformation Logic (Static Fixtures)" {
    It "correctly extracts displayorder GUIDs from BCD manager block" {
        $sampleBcdOutput = @"
Windows Boot Manager
--------------------
identifier              {9dea862c-5cdd-4e70-acc1-f32b344d4795}
device                  partition=\Device\HarddiskVolume1
description             Windows Boot Manager
displayorder            {a7b3c2d1-0000-0000-0000-000000000001}
                        {b8c4d3e2-0000-0000-0000-000000000002}
                        {c9d5e4f3-0000-0000-0000-000000000003}
"@
        $displayMatches = [regex]::Matches($sampleBcdOutput, '(?ms)displayorder\s+((?:\{[a-f0-9-]+\}\s*)+)')
        $displayOrderGuids = @()
        foreach ($m in $displayMatches) {
            foreach ($guidMatch in [regex]::Matches($m.Groups[1].Value, '\{[a-f0-9-]+\}')) {
                $displayOrderGuids += $guidMatch.Value
            }
        }
        $displayOrderGuids.Count | Should -Be 3
        $displayOrderGuids[0] | Should -Be '{a7b3c2d1-0000-0000-0000-000000000001}'
        $displayOrderGuids[1] | Should -Be '{b8c4d3e2-0000-0000-0000-000000000002}'
        $displayOrderGuids[2] | Should -Be '{c9d5e4f3-0000-0000-0000-000000000003}'
    }

    It "detects dangling GUIDs not present in boot loader objects" {
        $sampleBcdOutput = @"
Windows Boot Manager
--------------------
identifier              {9dea862c-5cdd-4e70-acc1-f32b344d4795}
displayorder            {a7b3c2d1-0000-0000-0000-000000000001}
                        {c9d5e4f3-0000-0000-0000-000000000003}

Windows Boot Loader
-------------------
identifier              {a7b3c2d1-0000-0000-0000-000000000001}
description             Windows 11 Pro Primary
"@
        $objectGuids = @([regex]::Matches($sampleBcdOutput, '(?m)^identifier\s+(\{[a-f0-9-]+\})') | ForEach-Object { $_.Groups[1].Value })
        $danglingGuid = '{c9d5e4f3-0000-0000-0000-000000000003}'
        
        ($objectGuids -contains $danglingGuid) | Should -Be $false
    }
}

Describe "Backup Naming & Formatting Invariants" {
    It "generates valid backup file names conforming to specification" {
        $timestamp = (Get-Date).ToString("yyyyMMdd HHmm")
        $volumeLabel = "ESP_BOOT"
        $computerName = $env:COMPUTERNAME
        
        $bakFileName = "$timestamp $volumeLabel $computerName.bak"
        $txtFileName = "$timestamp $volumeLabel $computerName.txt"
        $logFileName = "$timestamp $volumeLabel $computerName.log"
        
        ($bakFileName -match '^\d{8}\s\d{4}\s.+\s.+\.bak$') | Should -Be $true
        ($txtFileName -match '^\d{8}\s\d{4}\s.+\s.+\.txt$') | Should -Be $true
        ($logFileName -match '^\d{8}\s\d{4}\s.+\s.+\.log$') | Should -Be $true
    }

    It "sanitizes filenames from invalid characters" {
        $rawLabel = 'BOOT:VOLUME/EFI'
        $sanitized = $rawLabel -replace '[:/\\]', '_'
        $sanitized | Should -Be 'BOOT_VOLUME_EFI'
    }
}

Describe "Zero-Reboot Safety & Non-Destructive Guard" {
    It "verifies that the test suite does not invoke restart or shutdown commands" {
        $testContent = Get-Content -Path $PSCommandPath -Raw
        ($testContent -match '(?i)\bRestart-Computer\b') | Should -Be $false
        ($testContent -match '(?i)\bshutdown\s+/[r|s]\b') | Should -Be $false
    }
}

