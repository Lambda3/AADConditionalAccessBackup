# Backup for Azure Active Directory Conditional Access

Two .ps1 scripts used to backup and restore AAD Conditional Access.

## Running

Invoke the scripts, for example:

```powershell
.\backup.ps1 -Verbose
.\restore.ps1 -Date 11/29/2022 -Verbose -WhatIf
```

## Contributing

Questions, comments, bug reports, and pull requests are all welcome.  Submit them at
[the project on GitHub](https://github.com/Lambda3/AADConditionalAccessBackup).

Bug reports that include steps-to-reproduce (including code) are the
best. Even better, make them in the form of pull requests.

## Author

[Giovanni Bassi](https://twitter.com/giovannibassi).

## License

Licensed under the MIT License.
