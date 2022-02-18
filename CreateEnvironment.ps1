# *****************************************************************************
# *                                                                           *
# *             S C R I P T    P A R A M E T E R S                            *
# *                                                                           *
# *****************************************************************************
#
# Define the script parameters
Param
(
    [string] $file=".\envConfig.json", # command line specification of input file
    [bool] $createUsers = $true,
    [bool] $createDomains = $true,
    [bool] $createCANamedLocations = $true,
    [bool] $createCAGroups = $true,
    [bool] $createCAPolicies = $true
)
#
$SCRIPTNAME    = "Create-AzureADEnvironment"
$SCRIPTVERSION = "1.0.1"
$VersionUpdate = "2/03/2021 1:00 PM EST"
$Author = "John Serban"

write-host "******************************* SCRIPT START *********************"
write-host 
write-host "script : $SCRIPTNAME"
write-host "version: $SCRIPTVERSION"
write-host "date:    $VersionUpdate"
write-host "author:  $Author"
write-host
write-host "******************************************************************"
#
# *****************************************************************************
# *                                                                           *
# *             R E L E A S E   H I S T O R Y                                 *
# *                                                                           *
# *****************************************************************************
# COMMENT: This script creates Azure Role Assignable Groups from a .csv file.
#
#  Note: This script creates the intial configuration of an AAD tenant.
#
#  1.0.0  Initial release.
#
# *****************************************************************************
# *                                                                           *
# *             P R O G R A M   V A R I A B L E S                             *
# *                                                                           *
# *****************************************************************************
#
$reportInfo=@()
$starttime = Get-Date
$numFound=0
$numNotFound = 0
$numProcessed = 0
#
$defaultDirectory = (get-location).path
$dateStamp="_" + (Get-Date).ToString("yyyyMMdd") + "_" + (Get-Date).ToString("HHmm")
# set the name of the output file
$outputFile = $SCRIPTNAME + "_log_" + $dateStamp + ".csv"
#
#
# *****************************************************************************
# *                                                                           *
# *                F U N C T I O N S                                          *
# *                                                                           *
# *****************************************************************************
#
function my-LookupUserAndAddToList ($userList)
# Look up users and add their objectID to an array
{
    $userIdList=@()
    foreach ($u in $userList) 
    {
        $aadUser=$null
        $uFilter = "userPrincipalName eq '" + $u + "'"
        $aadUser=Get-MgUser -Filter $uFilter
        if ($null -notlike $aadUser) {
            $userIdList+=$aadUser.Id
        }
    } 
    Return $userIdList
}
#
function my-LookupGroupAndAddToList ($groupList)
# Look up groups and add their objectID to an array
{
    $groupIdList=@()
    foreach ($g in $groupList) 
    {
        $aadGroup=$null
        $gFilter = "displayName eq '" + $g + "'"
        $aadGroup=Get-MgGroup -Filter $gFilter
        if ($null -notlike $aadGroup) {
            $groupIdList+=$aadGroup.Id
        }
    } 
    Return $groupIdList
}
#
function my-LookupRoleAndAddToList ($roleList)
# Look up role and add their objectID to an array
{
    $roleIdList=@()
    $rtHashTable=my-createRoleTemplateHashtable
    foreach ($r in $roleList) 
    {
        If ($rtHashTable.ContainsKey($r)) {
            $roleIdList+=$rtHashTable[$r] 
        }
    } 
    Return $roleIdList

}
#
function my-createRoleTemplateHashtable 
# Create a hashtable with all Role Template displayNames and Ids
{
    $roleTemplateHT=@{}
    $aadRoleTemplates=Get-MgDirectoryRoleTemplate | Select-Object DisplayName,Id
    foreach ($rt in $aadRoleTemplates) 
    {
        $roleTemplateHT.Add("$($rt.DisplayName)","$($rt.Id)")
    } 
    Return $roleTemplateHT
}
# *****************************************************************************
# *                                                                           *
# *                M A I N  L O G I C  L O O P                                *
# *                                                                           *
# *****************************************************************************
#
Write-Host "Starting run at $starttime"
#
# Install NuGet package Provider if it is not already installed
if(!(Get-PackageProvider -Name NuGet)) { Install-PackageProvider -Name NuGet -Force }
#
# Set the executionPolicy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
#
# Install NuGet package Provider if it is not already installed for current users
if(!(Get-Module -Name "Microsoft.Graph")) { Install-Module Microsoft.Graph -Scope CurrentUser }
Import-Module Microsoft.Graph
#
# Install NuGet package Provider if it is not already installed for all users - REQUIRES ADMIN PRIVILEGES
#if(!(Get-Module -Name "Microsoft.Graph")) { Install-Module Microsoft.Graph -Scope AllUsers }
#
# Set the MgProfile to use the Beta Microsoft Graph REST api
#Select-MgProfile -Name "beta"
#
# Authenticate with the required permissions and scopes
# You'll need to sign in with an admin account to consent to the required scopes.
Connect-MgGraph -Scopes "Directory.ReadWrite.All" ,"RoleManagement.ReadWrite.Directory","Domain.ReadWrite.All","Policy.ReadWrite.ConditionalAccess","Policy.Read.All"
#
# Import the envConfig.json file 
$Config = ConvertFrom-Json -InputObject (Get-Content -Path $file -Raw);
$accounts = (($Config).accounts)
$domains = (($Config).domains)
$caLocations = (($Config).caLocations)
$caGroups = (($Config).caGroups)
$caPolicies = (($Config).caPolicies)
#
# Create Breakglass Global Administrators if they do not already exist
if ($createUsers) {
    foreach ($account in $accounts)
    {
        $uFilter = "userPrincipalName eq '" + $($account.userPrincipalName) + "'"
        $user=Get-MgUser -Filter $uFilter
        if ($null -like $user)
        {   
            Write-Host "User $($account.UserPrincipalname) not found - Attempting to create user"
            $PasswordProfile = @{
                Password = $account.Password
            }
            $user=New-MgUser -MailNickname $account.Username -DisplayName $account.UserDisplayName `
            -JobTitle $account.UserDescription -UserPrincipalName $account.UserPrincipalname `
            -PasswordProfile $PasswordProfile -AccountEnabled
            if ($null -like $user)
            {   
                $uStatus="ERROR"
                Write-Host $uStatus "-- User" $($account.UserPrincipalname) "not created" -ForegroundColor Red
            }
            else
            {   
                $ustatus="SUCCESS"
                Write-Host $uStatus "-- User" $($account.UserPrincipalname) "successfull created" -ForegroundColor Green
                # if user was successfully created, add them to the Global Admins role
                if ($uStatus -eq "SUCCESS")
                {
                    $gaRole=Get-MgDirectoryRole -Filter "DisplayName eq 'Global Administrator'"
                    $ht=@{}
                    $ht.Add("@odata.id","https://graph.microsoft.com/v1.0/directoryObjects/"+$user.Id)
                    New-MgDirectoryRoleMemberByRef -DirectoryRoleId $gaRole.Id -AdditionalProperties $ht
                }
            }
        }
    }
}
#
# Create Domains if they do not already exist
if ($createDomains) {
    foreach ($domain in $domains)
    {
        $dFilter = "Id eq '" + $($domain.DomainId) + "'"
        $azDomain=Get-MgDomain -Filter $dFilter -ErrorAction SilentlyContinue
        if ($null -like $azDomain)
        {
            Write-Host "Domain $($domain.DomainId) not found - Attempting to create domain"
            $AzDomain=New-MgDomain -Id $($domain.DomainId)
            if ($null -like $AzDomain)
            {   
                $dStatus="ERROR"
                Write-Host $dStatus "-- Domain" $($domain.DomainId) "creation failed" -ForegroundColor Red
            }
        }
        if (!($null -like $azDomain))
        {
            Write-Host "Warning -- Domain $azDomain.Id now exists in Azure AD - Register required DNS records and verify" -ForegroundColor Yellow
        }
    }
}
#
# Create CA Named Locations that are referenced in CA policies to be created if they do not already exist 
if ($createCANamedLocations) {
    foreach ($caLocation in $caLocations)
    {
        $nlFilter = "displayName eq '" + $($CaLocation.DisplayName) + "'"
        $azNamedLocation=Get-MgIdentityConditionalAccessNamedLocation -Filter $nlFilter
        if ($null -like $azNamedLocation)
        {
            Write-Host "Named Location $($CaLocations.DisplayName) not found - Attempting to create Named Location"
            # Create a list of all cidrAddress ranges
            $ipRangeList=@()
            foreach ($range in $caLocation.ipRanges) 
            {
                $ipRangeList+=@{
                    "cidrAddress" = $range.cidrAddress
                    "@odata.type" = "#microsoft.graph.iPv4CidrRange"
                } 
            }
            # Create the Named Location Parameter hashtable
            $params = @{
                "@odata.type" = "#microsoft.graph.ipNamedLocation"
                displayName = $caLocation.displayName
                isTrusted = $($caLocation.isTrusted)
                ipRanges = $ipRangeList
            }
            # Create the Named Location            
            $azNamedLocation=New-MgIdentityConditionalAccessNamedLocation -BodyParameter $params
            if ($null -like $azNamedLocation)
            {   
                $nlStatus="ERROR"
                Write-Host $nlStatus "-- Named Location" $($CaLocations.DisplayName) "creation failed" -ForegroundColor Red
            }
        }
        if (!($null -like $azNamedLocation))
        {
            $nlStatus="SUCCESS"
            Write-Host "$nlStatus -- Named Location $($azNamedLocation.Displayname) now exists in Azure AD" -ForegroundColor Green
            
        }
    }
}
#
# Create CA Security Groups that will be referenced in CA policies to be created if they do not already exist 
if ($createCAGroups) {
    foreach ($caGroup in $caGroups)
    {
        $gFilter = "displayName eq '" + $($caGroup.displayName) + "'"
        $azGroup=Get-MgGroup -Filter $gFilter
        if ($null -like $azGroup)
        {
            Write-Host "Group $($caGroup.DisplayName) not found - Attempting to create the group"
            if ($caGroup.mailEnabled.ToLower() -eq "true") {[bool]$mEnabled=$true} else {[bool]$mEnabled=$false}
            if ($caGroup.IsAssignableToRole.ToLower() -eq "true") {[bool]$isAssignableToRole=$true} else {[bool]$isAssignableToRole=$false}
            $azGroup=New-MgGroup -DisplayName $($caGroup.DisplayName) `
                -MailEnabled:$mEnabled `
                -MailNickname $($caGroup.mailNickname) `
                -SecurityEnabled `
                -Description $($caGroup.description) `
                -IsAssignableToRole:$IsAssignableToRole
            if ($null -like $azGroup)
            {   
                $grStatus="ERROR"
                Write-Host $grStatus "-- Group" $($caGroup.DisplayName) "creation failed" -ForegroundColor Red
            }
        }
        if (!($null -like $azGroup))
        {
            $grStatus="SUCCESS"
            Write-Host "$grStatus -- Group $($azGroup.Displayname) now exists in Azure AD" -ForegroundColor Green
            
        }
    }
}
#
# Create Conditional Access Policies
if ($createCAPolicies) {
    foreach ($caPolicy in $caPolicies)
    {
        $caFilter = "displayName eq '" + $($caPolicy.displayName) + "'"
        $azNamedLocation=Get-MgIdentityConditionalAccessNamedLocation -Filter $nlFilter
        $azCAPolicy=Get-MgIdentityConditionalAccessPolicy -Filter $caFilter
        if ($null -like $azCAPolicy)
        {
            Write-Host "Conditional Access Policy $($caPolicy.DisplayName) not found - Attempting to create CA Policy"
            # Add the object ID of users to be included to the CA policy 
            $includeUsersList=@()
            if ($caPolicy.includeUsers -eq "All") 
            {
                $includeUsersList+="All"
            }
            else
            {
                if (!($null -like $caPolicy.includeUsers)) {
                    $includeUsersList=my-LookupUserAndAddToList $caPolicy.includeUsers
                    if ($includeUsersList.count -ne $caPolicy.includeUsers.Count) {
                        Write-Host "ERROR - not all included users could be found in Azure AD and were not all added to the CA Policy" -ForegroundColor Red
                    } 
                    else {
                        Write-Host "Success - All users to be included have been added to the CA Policy" -ForegroundColor Green
                    }
                }
            }
            # Add the object ID of users to be excluded to the CA policy
            $excludeUsersList=@()
            if ($null -notlike $caPolicy.excludeUsers){
                $excludeUsersList=my-LookupUserAndAddToList $caPolicy.excludeUsers
                if ($excludeUsersList.count -ne $caPolicy.excludeUsers.Count) {
                    Write-Host "ERROR - not all excluded users could be found in Azure AD and were not all added to the CA Policy" -ForegroundColor Red
                } 
                else {
                    Write-Host "Success - All users to be excluded have been added to the CA Policy" -ForegroundColor Green
                }
            }
            # Add the object ID of groups to be included to the CA policy
            $includeGroupsList=@()
            if (!($null -like $caPolicy.includeGroups)) {
                $includeGroupsList=my-LookupGroupAndAddToList $caPolicy.includeGroups
                if ($includeGroupsList.count -ne $caPolicy.includeGroups.Count) {
                    Write-Host "ERROR - not all included groups could be found in Azure AD and were not all added to the CA Policy" -ForegroundColor Red
                } 
                else {
                    Write-Host "Success - All users to be included have been added to the CA Policy" -ForegroundColor Green
                } 
            }
            # Add the object ID of groups to be excluded to the CA policy
            $excludeGroupsList=@()
            if (!($null -like $caPolicy.includeGroups)) {
                $excludeGroupsList=my-LookupGroupAndAddToList $caPolicy.excludeGroups
                if ($excludeGroupsList.count -ne $caPolicy.includeGroups.Count) {
                    Write-Host "ERROR - not all excluded groups could be found in Azure AD and were not all added to the CA Policy" -ForegroundColor Red
                } 
                else {
                    Write-Host "Success - All groups to be excluded have been added to the CA Policy" -ForegroundColor Green
                } 
            }
            # Add the object ID of AAD Roles to be included to the CA policy
            $includeRolesList=@()
            if (!($null -like $caPolicy.includeRoles)) {
                $includeRolesList=my-LookupRoleAndAddToList $caPolicy.includeRoles
                if ($includeRolesList.count -ne $caPolicy.includeRoles.Count) {
                    Write-Host "ERROR - not all included roles could be found in Azure AD and were not all added to the CA Policy" -ForegroundColor Red
                } 
                else {
                    Write-Host "Success - All roles to be included have been added to the CA Policy" -ForegroundColor Green
                }
            }
            # Add the object ID of AAD Roles to be excluded to the CA policy
            $excludeRolesList=@()
            if (!($null -like $caPolicy.excludeRoles)) {
                $excludeRolesList=my-LookupRoleAndAddToList $caPolicy.excludeRoles
                if ($excludeRolesList.count -ne $caPolicy.excludeRoles.Count) {
                    Write-Host "ERROR - not all excluded roles could be found in Azure AD and were not all added to the CA Policy" -ForegroundColor Red
                } 
                else {
                    Write-Host "Success - All roles to be excluded have been added to the CA Policy" -ForegroundColor Green
                }
            }
            # Add the object ID of AAD Named Locations to be excluded to the CA policy
            $includeLocationsList=@()
            if ($caPolicy.locations.includeLocations.ToLower() -eq "all") 
            {
                $includeLocationsList+="All"
            }
            else
            {
                foreach ($location in $caPolicy.locations.includeLocations)
                {
                    $nlFilter = "displayName eq '" + $($location) + "'"
                    $azNamedLocation=Get-MgIdentityConditionalAccessNamedLocation -Filter $nlFilter
                    if ($null -notlike $azNamedLocation)
                    {
                        $includeLocationsList+=$azNamedLocation.Id
                    }
                }
                if ($includeLocationsList.count -ne $caPolicy.locations.includeLocations.Count) {
                    Write-Host "ERROR - not all included Named Locations could be found in Azure AD and were not all added to the CA Policy" -ForegroundColor Red
                } 
                else {
                    Write-Host "Success - All Named Locations to be included have been added to the CA Policy" -ForegroundColor Green
                }
            }
            # Add the object ID of AAD Named Locations to be excluded to the CA policy
            $excludeLocationsList=@()
            foreach ($location in $caPolicy.locations.excludeLocations)
            {
                $nlFilter = "displayName eq '" + $($location) + "'"
                $azNamedLocation=Get-MgIdentityConditionalAccessNamedLocation -Filter $nlFilter
                if ($null -notlike $azNamedLocation)
                {
                    $excludeLocationsList+=$azNamedLocation.Id
                }
            }
            if ($excludeLocationsList.count -ne $caPolicy.locations.excludeLocations.Count) {
                Write-Host "ERROR - not all excluded Named Locations could be found in Azure AD and were not all added to the CA Policy" -ForegroundColor Red
            } 
            else {
                Write-Host "Success - All Named Locations to be included have been added to the CA Policy" -ForegroundColor Green
            }
            #
            # Create the CA Policy Users Parameters hashtable
            $conditionsParams = @{
                userRiskLevels=$caPolicy.userRiskLevels
                signInRiskLevels=$caPolicy.signInRiskLevels
                clientAppTypes=$caPolicy.clientAppTypes
                platforms=$caPolicy.platforms
                devices=$caPolicy.devices
                applications = @{
                    includeApplications=$caPolicy.includeApplications
                    excludeApplications=$caPolicy.excludeApplications
                    includeUserActions=$caPolicy.includeUserActions
                    includeAuthenticationContextClassReferences=$caPolicy.includeAuthenticationContextClassReferences
                }
                users = @{ 
                    includeUsers=$includeUsersList
                    excludeUsers=$excludeUsersList
                    includeGroups=$includeGroupsList
                    excludeGroups=$excludeGroupsList
                    includeRoles=$includeRolesList
                    excludeRoles=$excludeRolesList
                }
                locations=@{
                    includeLocations=$includeLocationsList
                    excludeLocations=$excludeLocationsList
                }
            }
            #
            # Create the CA Policy grantControls Parameters hashtable
            if (!($null -like $caPolicy.grantControls.operator)) {
                $grantControlsParams = @{
                    operator=$caPolicy.grantControls.operator
                    builtInControls=$caPolicy.grantControls.builtInControls
                    customAuthenticationFactors=$null
                    termsOfUse=$null
                }
            }
            #
            ## Create the CA Policy signInFrequency Parameters hashtable
            if ($null -like $caPolicy.signInFrequency) {
                $sessionControlsParams=$null
            }
            else
            {
                $sessionControlsParams = @{
                    disableResilienceDefaults=$false
                    applicationEnforcedRestrictions=$null
                    cloudAppSecurity=$null
                    persistentBrowser=$null
                    signInFrequency=@{
                        IsEnabled = $caPolicy.SignInFrequency.IsEnabled
                        type = $caPolicy.SignInFrequency.Type
                        value = $caPolicy.SignInFrequency.Value
                    }
                }
            }

            # Create the CA Policy Location  
            if ($null -like $sessionControlsParams) {
                # Create CA Policy without SessionControls
                $azCAPolicy=New-MgIdentityConditionalAccessPolicy `
                    -DisplayName $CaPolicy.displayName `
                    -State $CaPolicy.state `
                    -Conditions $conditionsParams `
                    -GrantControls $grantControlsParams
            }
            else {         
                # Create CA Policy with SessionControls included
                $azCAPolicy=New-MgIdentityConditionalAccessPolicy `
                    -DisplayName $CaPolicy.displayName `
                    -State $CaPolicy.state `
                    -Conditions $conditionsParams `
                    -GrantControls $grantControlsParams `
                    -SessionControls $sessionControlsParams 
            }
            #
            # Report the policy creation status
            if ($null -like $azCAPolicy)
            {   
                $caStatus="ERROR"
                Write-Host $caStatus "-- Conditional Access Policy " $($CaPolicy.displayName) "creation failed" -ForegroundColor Red
            }
            else
            {
                $caStatus="SUCCESS"
                Write-Host "$caStatus -- Conditional Access Policy $($azCAPolicy.Displayname) created" -ForegroundColor Green
            }
        }
    }
}
