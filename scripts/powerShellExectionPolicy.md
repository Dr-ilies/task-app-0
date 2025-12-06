user powerShell as admin and execute the following commends:


# bash
PS C:\WINDOWS\system32> Get-ExecutionPolicy -List

    Scope ExecutionPolicy
    ----- ---------------
MachinePolicy       Undefined
   UserPolicy       Undefined
      Process    Unrestricted
  CurrentUser    Unrestricted
 LocalMachine    Unrestricted
To unrestrict the execution policy:


# bash
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser


Under your normal user. The following requires to open an administrator instance:


# bash
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine

as an administrator.
You might need to restart the computer afterwards.