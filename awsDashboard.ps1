# Get the remote server names and application names

[xml]$configuration = Get-Content .\Server_Config.xml
$Result = @() 
ForEach($system in $configuration.Configuration.computers) 
{	
	$computer  = $system.Name
	write-host $computer
	$processor = Get-WmiObject -computername $computer win32_processor | Measure-Object -property LoadPercentage -Average | Select Average #Get CPU Information
	$OS = Get-WmiObject win32_operatingsystem -computername $computer | Select-Object @{Name = "MemoryUsage"; Expression = {“{0:N2}” -f ((($_.TotalVisibleMemorySize - $_.FreePhysicalMemory)*100)/ $_.TotalVisibleMemorySize) }}
	$volc = Get-WmiObject -Class win32_Volume -ComputerName $computer -Filter "DriveLetter = 'C:'" | Select-object @{Name = "CDrive"; Expression = {“{0:N2}” -f  (($_.FreeSpace / $_.Capacity)*100) } }
	$vold = Get-WmiObject -Class win32_Volume -ComputerName $computer -Filter "DriveLetter = 'D:'" | Select-object @{Name = "DDrive"; Expression = {“{0:N2}” -f  (($_.FreeSpace / $_.Capacity)*100) } }
	$cores = @{"t2.nano" = "1"; "t2.micro" = "1"; "t2.small" = "1"; "t2.medium" = "2"; "t2.large" = "2"; "t2.xlarge" = "8"; "m4.xlarge" = "2"; "m4.large" = "2"}
	Import-Module WebAdministration
	$IISAppPool = Get-WmiObject -Class applicationpool -Authentication PacketPrivacy -Impersonation Impersonate -Computer $computer -Namespace root\webadministration | Select Name, @{Expression={if($_.GetState().ReturnValue -eq 1){"Started"}else{"Not Started"}};Label="State"}
	foreach ($pool in $IISAppPool)
	{
		foreach($apps in $system.ApppoolName){ # Loop through the collection and find the status of the appPool
			if($apps -eq $pool.Name){	
				Write-Host $apps
				$instanses = Get-EC2Tag | where {$_.ResourceType -eq "instance"} | Where-Object{$_.Value -eq "$computer"}  
				$instanceId = $instanses.ResourceId												
				$instance = Get-EC2InstanceStatus -InstanceId $instanceId | Select AvailabilityZone
				$InstanceType = (Get-EC2Instance -InstanceId $instanceId).Instances.InstanceType.Value
				$upTime =(Get-EC2Instance -InstanceId $instanceId).Instances.LaunchTime	
				$NT = [pscustomobject]@{Status=''}
				if(!$system.NTServiceID){					
					$NT.Status = "NA"
				}else{
					$NT = Get-Service | Where-Object {$_.name -eq $system.NTServiceID } | Select Status
				}
				$w3svc = Get-Service | Where-Object {$_.name -eq "W3SVC" } | Select Status
				$WAS = Get-Service | Where-Object {$_.name -eq "WAS" } | Select Status		
				$Result += [PSCustomObject]@{
					"ServerName" = "$computer" 
					"ResourceId" = "$instanceId"		
					"upTime" = "$upTime"		
					"zone" = $instance.AvailabilityZone	
					"appName" = $pool.Name
					"PoolStatus" = $pool.State 
					"CPU" = "$($processor.Average)%"
					"vCPU" = $cores.Get_Item($InstanceType)
					"memory" = "$($OS.MemoryUsage)%"
					"CDrive" = "$($volc.CDrive)%"
					"DDrive" = "$($vold.DDrive)%"
					"NT" = $NT.Status
					"W3SVC" = $w3svc.Status
					"WAS" = $WAS.Status
				}
			}
		}				
	}	
}	

write-host $Result

$OutputHTML = "<html> <title>Application & Instance Monitoring</title> 
	</head><body> <table width='1200'> <tr bgcolor='#f0f3f5'> <td colspan='7' height='48' align='center' valign=""middle""> 
	<font face='Helvetica Neue' color='#151b1e' size='4'><strong>Application & Instance Monitoring </strong></font> </t> </tr> 
	</table><table width='1200'> <tbody> <tr bgcolor=#c2cfd6> <td width='6%' align='center'><strong>Server Name</strong></td> 
	<td width='6%' align='center'><strong>Instance ID</strong> </td><td width='6%' align='center'><strong>Uptime</strong></td>
	<td width='6%' align='center'><strong>Availability zone</strong></td> <td width='4%' align='center'><strong>no of vCPU</strong></td> 
	<td width='6%' align='center'><strong>AppPool Name</strong></td> <td width='4%' align='center'><strong>AppPool Status</strong></td>	
	<td width='6%' align='center'><strong>CPU Utilization</strong></td> <td width='6%' align='center'><strong>Memory Utilization</strong></td> 
	<td width='4%' align='center'><strong>C Drive </strong></td> <td width='4%' align='center'><strong>D Drive </strong></td>  	
	<td width='6%' align='center'><strong>NT Services</strong></td> <td width='4%' align='center'><strong>W3SVC</strong></td> 
	<td width='4%' align='center'><strong>WAS</strong></td> </tr>"

Foreach($Entry in $Result) {
	$red = '#B22222'
	$green = '#387C44'
	$NA = '#CCCCCC'
	[decimal]$cputhreshold = 80
	if($Entry.CPU -gt [decimal]$cputhreshold){ $CPUcolorcode = $red} else { $CPUcolorcode = $green}
	if($Entry.W3SVC -eq "Running"){ $W3SVCcolorcode = $green} else { $W3SVCcolorcode = $red }
	if($Entry.WAS -eq "Running"){ $WAScolorcode = $green} else { $WAScolorcode = $red }
	if($Entry.NT -eq "Running") { $NTcolorcode = $green} else { $NTcolorcode = $red }
	if($Entry.NT -eq "NA"){ $NTcolorcode = $NA } 
	$OutputHTML += "
	<td bgcolor='#CCCCCC' align=center><font color='#003399'>$($Entry.ServerName)</font></td> <td bgcolor='#CCCCCC' align=center> $($Entry.ResourceId)</td> 
	<td bgcolor='#CCCCCC' align=center> $($Entry.upTime) </td> <td bgcolor='#CCCCCC' align=center> $($Entry.zone)</td> 
	<td bgcolor='#CCCCCC' align=center>$($Entry.vCPU)</td> <td bgcolor='#CCCCCC' align=center> $($Entry.appName)</td> 
	<td bgcolor='#387C44' align=center> $($Entry.PoolStatus) </td> <td bgcolor=$($CPUcolorcode) align=center> $($Entry.CPU)</td> 
	<td bgcolor='#387C44' align=center> $($Entry.memory)</td> <td bgcolor='#387C44' align=center> $($Entry.CDrive)</td> 
	<td bgcolor='#387C44' align=center> $($Entry.DDrive)</td> <td bgcolor=$($NTcolorcode) align=center> $($Entry.NT) </td> 
	<td bgcolor=$($W3SVCcolorcode) align=center> $($Entry.W3SVC)</td> 
	<td bgcolor=$($WAScolorcode) align=center> $($Entry.WAS)</td> </tr>"
}
$OutputHTML += "</tbody></rable></body></html>" 
$OutputHTML | out-file .\awsDashboard.htm
Invoke-Expression .\awsDashboard.htm  

##Send email functionality

$smtp = $configuration.Configuration.EmailConfiguration
 
$smtpServer    = $smtp.SMTPServer
$emailFrom     = $smtp.EmailFrom
$emailTo       = $smtp.EmailTo
$emailSubject  = (" AWS PreProd Instances Monitoring Report - " + (Get-Date )+" CST")
 
Send-MailMessage -To $emailTo -Subject $emailSubject -From $emailFrom -SmtpServer $smtpServer -Attachment (Get-ChildItem -Path 'D:\temp\instancemonitoring.htm' -File)
