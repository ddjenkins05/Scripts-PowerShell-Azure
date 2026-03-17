<#
.SYNOPSIS
Two simple Azure PowerShell scripts in one file:
  1) List subscriptions (Name, Id, State)
  2) Set the active subscription context

.DESCRIPTION
Script 1: Uses Get-AzSubscription to show Name, Id, and State.
Script 2: Uses Set-AzContext to set the current session context to a subscription.

.NOTES
Requires Az.Accounts (part of the Az module).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Script 1 - List subscriptions
# Lists subscriptions the current account can access.
Get-AzSubscription | Select-Object Name, Id, State
#endregion

#region Script 2 - Set subscription context
# Example usage:
#   Set-AzContext -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
# or
#   Set-AzContext -SubscriptionName "MyDevelopmentSubscription"

# Uncomment ONE of the following lines and provide your value:
# Set-AzContext -SubscriptionId "PUT-SUBSCRIPTION-GUID-HERE"
# Set-AzContext -SubscriptionName "PUT-SUBSCRIPTION-NAME-HERE"
#endregion
