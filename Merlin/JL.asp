<!DOCTYPE html
	PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">

<head>
	<meta http-equiv="X-UA-Compatible" content="IE=Edge">
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
	<meta HTTP-EQUIV="Pragma" CONTENT="no-cache">
	<meta HTTP-EQUIV="Expires" CONTENT="-1">
	<link rel="shortcut icon" href="images/favicon.png">
	<link rel="icon" href="images/favicon.png">
	<title>JL</title>
	<link rel="stylesheet" type="text/css" href="index_style.css">
	<link rel="stylesheet" type="text/css" href="form_style.css">
	<script language="JavaScript" type="text/javascript" src="/state.js"></script>
	<script language="JavaScript" type="text/javascript" src="/general.js"></script>
	<script language="JavaScript" type="text/javascript" src="/popup.js"></script>
	<script language="JavaScript" type="text/javascript" src="/help.js"></script>
	<script type="text/javascript" language="JavaScript" src="/validator.js"></script>
	<script>
		var custom_settings = <% get_custom_settings(); %>;
		//var custom_settings = {};

		var settings_list = {
			jl_creboot: 'false',
			jl_creboot_target_uptime: '',
			jl_creboot_hour: 4,
			jl_creboot_minute: 0,
			jl_disablewps: 'false',
			jl_fdns: 'false',
			jl_fdns_server: '',
			jl_fdns_server6: '',
			jl_fdns_permit_mac: '',
			jl_fdns_permit_ip: '',
			jl_fdns_permit_ip6: '',
			jl_fdns_require_iface: '',
			jl_fdns_fallback: '',
			jl_fdns_fallback6: '',
			jl_fdns_block_router_dns: 'false',
			jl_ledcontrol: 'false',
			jl_ledcontrol_on_hour: 6,
			jl_ledcontrol_on_minute: 0,
			jl_ledcontrol_off_hour: 0,
			jl_ledcontrol_off_minute: 0,
			jl_pkiller: 'false',
			jl_pkiller_processes: '',
			jl_rbackup: 'false',
			jl_rbackup_parameters: '--buffer-size 1M',
			jl_rbackup_remote: 'remote:',
			jl_rbackup_rclone_path: '',
			jl_rbackup_hour: 6,
			jl_rbackup_minute: 0,
			jl_rbackup_monthday: '*',
			jl_rbackup_weekday: '7',
			jl_swap: 'false',
			jl_swap_file: '',
			jl_swap_size: 1310721,
			jl_syslog: 'false',
			jl_syslog_log_file: '/tmp/syslog-moved.log',
			jl_twarning: 'false',
			jl_twarning_ttarget: 80,
			jl_twarning_cooldown: 300,
			jl_unotify: 'false',
			jl_unotify_bot_token: '',
			jl_unotify_chat_id: '',
			jl_usbnetwork: 'false',
		};

		function initial() {
			SetCurrentPage();
			show_menu();

			/* Load used config variables */
			for (var k in settings_list){
				if (settings_list.hasOwnProperty(k)) {
					var elements = document.querySelectorAll('#' + k);

					for (d = 0; d < elements.length; ++d) {
						element = elements[d]
							
						if (element) {
							switch (element.type.toLowerCase()) {
								case 'text':
								case 'select-one':
									if (custom_settings[k] == undefined)
										element.value = settings_list[k];
									else
										element.value = custom_settings[k];
									break;
								case 'radio':
									if (custom_settings[k] == undefined) {
										if (element.value == settings_list[k]) {
											element.setAttribute('checked', 'checked');
										}
									} else {
										if (element.value == custom_settings[k]) {
											element.setAttribute('checked', 'checked');
										}
									}
									break;
								default:
									console.log('Unsupported element (#' + k + ') type: ' + element.type);
							}
						}
					}
				}
			}
		}

		function SetCurrentPage() {
			/* Set the proper return pages */
			document.form.next_page.value = window.location.pathname.substring(1);
			document.form.current_page.value = window.location.pathname.substring(1);
		}

		function applySettings() {
			/* Retrieve value from input fields, and store in object */
			for (var k in settings_list){
				if (settings_list.hasOwnProperty(k)) {
					/*var element = document.getElementById(k);
					if (element) {
						if (custom_settings[k] != undefined || element.value != settings_list[k])
							custom_settings[k] = element.value
					}*/

					var elements = document.querySelectorAll('#' + k);

					for (d = 0; d < elements.length; ++d) {
						element = elements[d]

						if (element) {
							switch (element.type.toLowerCase()) {
								case 'radio':
									if (element.getAttribute('checked') != 'checked') {
										continue;
									}
								case 'text':
								case 'select-one':
									if (custom_settings[k] != undefined || element.value != settings_list[k])
										custom_settings[k] = element.value
									break;
								default:
									console.log('Unsupported element (#' + k + ') type: ' + element.type);
							}
						}
					}
				}
			}

			console.log(custom_settings);

			/* Store object as a string in the amng_custom hidden input field */
			document.getElementById('amng_custom').value = JSON.stringify(custom_settings);

			/* Apply */
			showLoading();
			document.form.submit();
		}

		function handleRadioButton(element, event) {
			var elements = document.querySelectorAll('#' + element.id);
		
			for (e = 0; e < elements.length; ++e) {
				elements[e].removeAttribute('checked');
			}

			element.setAttribute('checked', 'checked');
		}
	</script>
</head>

<body onload="initial();" class="bg">
	<div id="TopBanner"></div>
	<div id="Loading" class="popup_bg"></div>
	<iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>
	<form method="post" name="form" action="start_apply.htm" target="hidden_frame">
		<input type="hidden" name="current_page" value="JL.asp">
		<input type="hidden" name="next_page" value="JL.asp">
		<input type="hidden" name="group_id" value="">
		<input type="hidden" name="modified" value="0">
		<input type="hidden" name="action_mode" value="apply">
		<input type="hidden" name="action_wait" value="5">
		<input type="hidden" name="first_time" value="">
		<input type="hidden" name="action_script" value="">
		<input type="hidden" name="preferred_lang" id="preferred_lang" value="<% nvram_get(" preferred_lang"); %>">
		<input type="hidden" name="firmver" value="<% nvram_get(" firmver"); %>">
		<input type="hidden" name="amng_custom" id="amng_custom" value="">

		<table class="content" align="center" cellpadding="0" cellspacing="0">
			<tr>
				<td width="17">&nbsp;</td>
				<td valign="top" width="202">
					<div id="mainMenu"></div>
					<div id="subMenu"></div>
				</td>
				<td valign="top">
					<div id="tabMenu" class="submenuBlock"></div>
					<table width="98%" border="0" align="left" cellpadding="0" cellspacing="0">
						<tr>
							<td align="left" valign="top">
								<table width="760px" border="0" cellpadding="5" cellspacing="0" bordercolor="#6b8fa3"
									class="FormTitle" id="FormTitle">
									<tr>
										<td bgcolor="#4D595D" colspan="3" valign="top">
											<div>&nbsp;</div>
											<div class="formfonttitle">JL</div>
											<div style="margin:10px 0 10px 5px;" class="splitLine"></div>
											<div class="formfontdesc">
												<#1838#>
											</div>

											<input type="hidden" name="action_script" value="restart_JL">
											
											<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable">
												<thead>
													<tr>
														<td colspan="2">Conditional reboot</td>
													</tr>
												</thead>
												<tbody>
													<tr>
														<th>Enabled</th>
														<td>
															<input type="radio" value="true" id="jl_creboot" name="jl_creboot" class="input" onchange="return handleRadioButton(this, event)">Yes
															<input type="radio" value="false" id="jl_creboot" name="jl_creboot" class="input" onchange="return handleRadioButton(this, event)">No
														</td>
													</tr>
													<tr>
														<th>Uptime Target</th>
														<td>
															<input type="text" maxlength="100" class="input_15_table" id="jl_creboot_target_uptime" onkeypress="return validator.isNumber(this,event);" autocorrect="off" autocapitalize="off">
															<span style="padding: 0 10px">In seconds</span>
														</td>
													</tr>
													<tr>
														<th>Run at</th>
														<td>
															<input type="text" maxlength="2" class="input_3_table" id="jl_creboot_hour" onkeypress="return validator.isNumber(this,event);" onblur="validator.timeRange(this, 0);" autocorrect="off" autocapitalize="off"> :
															<input type="text" maxlength="2" class="input_3_table" id="jl_creboot_minute" onkeypress="return validator.isNumber(this,event);" onblur="validator.timeRange(this, 1);" autocorrect="off" autocapitalize="off">
														</td>
													</tr>
												</tbody>
											</table>

											<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable">
												<thead>
													<tr>
														<td colspan="2">Force disable WPS</td>
													</tr>
												</thead>
												<tbody>
													<tr>
														<th>Enabled</th>
														<td>
															<input type="radio" value="true" id="jl_disablewps" name="jl_disablewps" class="input" onchange="return handleRadioButton(this, event)">Yes
															<input type="radio" value="false" id="jl_disablewps" name="jl_disablewps" class="input" onchange="return handleRadioButton(this, event)">No
														</td>
													</tr>
												</tbody>
											</table>

											<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable">
												<thead>
													<tr>
														<td colspan="2">Led control</td>
													</tr>
												</thead>
												<tbody>
													<tr>
														<th>Enabled</th>
														<td>
															<input type="radio" value="true" id="jl_ledcontrol" name="jl_ledcontrol" class="input" onchange="return handleRadioButton(this, event)">Yes
															<input type="radio" value="false" id="jl_ledcontrol" name="jl_ledcontrol" class="input" onchange="return handleRadioButton(this, event)">No
														</td>
													</tr>
													<tr>
														<th>Enable LEDs at</th>
														<td>
															<input type="text" maxlength="2" class="input_3_table" id="jl_ledcontrol_on_hour" onkeypress="return validator.isNumber(this,event);" onblur="validator.timeRange(this, 0);" autocorrect="off" autocapitalize="off"> :
															<input type="text" maxlength="2" class="input_3_table" id="jl_ledcontrol_on_minute" onkeypress="return validator.isNumber(this,event);" onblur="validator.timeRange(this, 1);" autocorrect="off" autocapitalize="off">
														</td>
													</tr>
													<tr>
														<th>Disable LEDs at</th>
														<td>
															<input type="text" maxlength="2" class="input_3_table" id="jl_ledcontrol_off_hour" onkeypress="return validator.isNumber(this,event);" onblur="validator.timeRange(this, 0);" autocorrect="off" autocapitalize="off"> :
															<input type="text" maxlength="2" class="input_3_table" id="jl_ledcontrol_off_minute" onkeypress="return validator.isNumber(this,event);" onblur="validator.timeRange(this, 1);" autocorrect="off" autocapitalize="off">
														</td>
													</tr>
												</tbody>
											</table>


											<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable">
												<thead>
													<tr>
														<td colspan="2">Force DNS</td>
													</tr>
												</thead>
												<tbody>
													<tr>
														<th>Enabled</th>
														<td>
															<input type="radio" value="true" id="jl_fdns" name="jl_fdns" class="input" onchange="return handleRadioButton(this, event)">Yes
															<input type="radio" value="false" id="jl_fdns" name="jl_fdns" class="input" onchange="return handleRadioButton(this, event)">No
														</td>
													</tr>
													<tr>
														<th>DNS Server</th>
														<td>
															IPv4: <input type="text" class="input_15_table" id="jl_fdns_server" onkeypress="return validator.isString(this, event)" autocorrect="off" autocapitalize="off">
															<br>
															IPv6: <input type="text" class="input_15_table" id="jl_fdns_server6" onkeypress="return validator.isString(this, event)" autocorrect="off" autocapitalize="off">
														</td>
													</tr>
													<tr>
														<th>Permitted hosts</th>
														<td>
															MAC: <input type="text" class="input_32_table" id="jl_fdns_permit_mac" onkeypress="return validator.isString(this, event)" autocorrect="off" autocapitalize="off">
															<br>
															IPv4: <input type="text" class="input_32_table" id="jl_fdns_permit_ip" onkeypress="return validator.isString(this, event)" autocorrect="off" autocapitalize="off">
															<br>
															IPv6: <input type="text" class="input_32_table" id="jl_fdns_permit_ip6" onkeypress="return validator.isString(this, event)" autocorrect="off" autocapitalize="off">
															<br>
															<span id="faq" style="padding: 0;">Separated by space.</span>
														</td>
													</tr>
													<tr>
														<th>Require interface</th>
														<td>
															<input type="radio" value="true" id="jl_fdns_require_iface" name="jl_fdns_require_iface" class="input" onchange="return handleRadioButton(this, event)">Yes
															<input type="radio" value="false" id="jl_fdns_require_iface" name="jl_fdns_require_iface" class="input" onchange="return handleRadioButton(this, event)">No
														</td>
													</tr>
													<tr>
														<th>Fallback DNS Server</th>
														<td>
															IPv4: <input type="text" class="input_15_table" id="jl_fdns_fallback" onkeypress="return validator.isString(this, event)" autocorrect="off" autocapitalize="off">
															<br>
															IPv6: <input type="text" class="input_15_table" id="jl_fdns_fallback6" onkeypress="return validator.isString(this, event)" autocorrect="off" autocapitalize="off">
														</td>
													</tr>
													<tr>
														<th>Block access to router's DNS</th>
														<td>
															<input type="radio" value="true" id="jl_fdns_block_router_dns" name="jl_fdns_block_router_dns" class="input" onchange="return handleRadioButton(this, event)">Yes
															<input type="radio" value="false" id="jl_fdns_block_router_dns" name="jl_fdns_block_router_dns" class="input" onchange="return handleRadioButton(this, event)">No
														</td>
													</tr>
												</tbody>
											</table>

											<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable">
												<thead>
													<tr>
														<td colspan="2">Kill processes on startup</td>
													</tr>
												</thead>
												<tbody>
													<tr>
														<th>Enabled</th>
														<td>
															<input type="radio" value="true" id="jl_pkiller" name="jl_pkiller" class="input" onchange="return handleRadioButton(this, event)">Yes
															<input type="radio" value="false" id="jl_pkiller" name="jl_pkiller" class="input" onchange="return handleRadioButton(this, event)">No
															<span id="faq" style="padding: 0 10px">Switching from enabled to disabled requires a reboot.</span>
														</td>
													</tr>
													<tr>
														<th>Processes/modules to kill and block</th>
														<td>
															<input type="text" class="input_32_table" id="jl_pkiller_processes" onkeypress="return validator.isString(this, event)" autocorrect="off" autocapitalize="off">
															<span id="faq" style="padding: 0 10px">Separated by space, full paths preferred.</span>
														</td>
													</tr>
												</tbody>
											</table>

											<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable">
												<thead>
													<tr>
														<td colspan="2">
															Automatically run backups (using Rclone)
														</td>
													</tr>
												</thead>
												<tbody>
													<tr>
														<th>Enabled</th>
														<td>
															<input type="radio" value="true" id="jl_rbackup" name="jl_rbackup" class="input" onchange="return handleRadioButton(this, event)">Yes
															<input type="radio" value="false" id="jl_rbackup" name="jl_rbackup" class="input" onchange="return handleRadioButton(this, event)">No
														</td>
													</tr>
													<tr>
														<th>Rclone path</th>
														<td>
															<input type="text" class="input_32_table" id="jl_rbackup_rclone_path" onkeypress="return validator.isString(this, event)" autocorrect="off" autocapitalize="off">
														</td>
													</tr>
													<tr>
														<th>Rclone extra parameters</th>
														<td>
															<input type="text" class="input_32_table" id="jl_rbackup_parameters" onkeypress="return validator.isString(this, event)" autocorrect="off" autocapitalize="off">
														</td>
													</tr>
													<tr>
														<th>Rclone remote</th>
														<td>
															<input type="text" class="input_15_table" id="jl_rbackup_remote" onkeypress="return validator.isString(this, event)" autocorrect="off" autocapitalize="off">
														</td>
													</tr>
													<tr>
														<th>Run at</th>
														<td>
															<input type="text" maxlength="2" class="input_3_table" id="jl_rbackup_hour" onkeypress="return validator.isNumber(this,event);" onblur="validator.timeRange(this, 0);" autocorrect="off" autocapitalize="off"> :
															<input type="text" maxlength="2" class="input_3_table" id="jl_rbackup_minute" onkeypress="return validator.isNumber(this,event);" onblur="validator.timeRange(this, 1);" autocorrect="off" autocapitalize="off"> &nbsp;
															<br>
															Day of the month:
															<input type="text" maxlength="2" class="input_3_table" id="jl_rbackup_monthday" onkeypress="return validator.isNumber(this,event);" onblur="validator.timeRange(this, 1);" autocorrect="off" autocapitalize="off">
															<br>
															Day of the week:
															<input type="text" maxlength="2" class="input_3_table" id="jl_rbackup_weekday" onkeypress="return validator.isNumber(this,event);" onblur="validator.timeRange(this, 1);" autocorrect="off" autocapitalize="off">
														</td>
													</tr>
												</tbody>
											</table>

											<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable">
												<thead>
													<tr>
														<td colspan="2">
															Automatically mount swap
														</td>
													</tr>
												</thead>
												<tbody>
													<tr>
														<th>Enabled</th>
														<td>
															<input type="radio" value="true" id="jl_swap" name="jl_swap" class="input" onchange="return handleRadioButton(this, event)">Yes
															<input type="radio" value="false" id="jl_swap" name="jl_swap" class="input" onchange="return handleRadioButton(this, event)">No
														</td>
													</tr>
													<tr>
														<th>Swap file</th>
														<td>
															<input type="text" class="input_32_table" id="jl_swap_file" onkeypress="return validator.isString(this, event)" autocorrect="off" autocapitalize="off">
														</td>
													</tr>
													<tr>
														<th>Swap size</th>
														<td>
															<input type="text" class="input_15_table" id="jl_swap_size" onkeypress="return validator.isNumber(this,event);" autocorrect="off" autocapitalize="off">
														</td>
													</tr>
												</tbody>
											</table>

											<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable">
												<thead>
													<tr>
														<td colspan="2">Move syslog to different location</td>
													</tr>
												</thead>
												<tbody>
													<tr>
														<th>Enabled</th>
														<td>
															<input type="radio" value="true" id="jl_syslog" name="jl_syslog" class="input" onchange="return handleRadioButton(this, event)">Yes
															<input type="radio" value="false" id="jl_syslog" name="jl_syslog" class="input" onchange="return handleRadioButton(this, event)">No
														</td>
													</tr>
													<tr>
														<th>Log file</th>
														<td>
															<input type="text" maxlength="100" class="input_32_table" id="jl_syslog_log_file" onkeypress="return validator.isString(this, event)" autocorrect="off" autocapitalize="off">
														</td>
													</tr>
												</tbody>
											</table>

											<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable">
												<thead>
													<tr>
														<td colspan="2">Temperature warning</td>
													</tr>
												</thead>
												<tbody>
													<tr>
														<th>Enabled</th>
														<td>
															<input type="radio" value="true" id="jl_twarning" name="jl_twarning" class="input" onchange="return handleRadioButton(this, event)">Yes
															<input type="radio" value="false" id="jl_twarning" name="jl_twarning" class="input" onchange="return handleRadioButton(this, event)">No
														</td>
													</tr>
													<tr>
														<th>Temperature threshold</th>
														<td>
															<input type="text" class="input_15_table" id="jl_twarning_ttarget" onkeypress="return validator.isNumber(this,event);" autocorrect="off" autocapitalize="off">
														</td>
													</tr>
													<tr>
														<th>Cooldown</th>
														<td>
															<input type="text" class="input_15_table" id="jl_twarning_cooldown" onkeypress="return validator.isNumber(this,event);" autocorrect="off" autocapitalize="off">
														</td>
													</tr>
												</tbody>
											</table>

											<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable">
												<thead>
													<tr>
														<td colspan="2">Send update notifications through Telegram</td>
													</tr>
												</thead>
												<tbody>
													<tr>
														<th>Enabled</th>
														<td>
															<input type="radio" value="true" id="jl_unotify" name="jl_unotify" class="input" onchange="return handleRadioButton(this, event)">Yes
															<input type="radio" value="false" id="jl_unotify" name="jl_unotify" class="input" onchange="return handleRadioButton(this, event)">No
														</td>
													</tr>
													<tr>
														<th>Bot Token</th>
														<td>
															<input type="text" maxlength="100" class="input_32_table" id="jl_unotify_bot_token" onkeypress="return validator.isString(this, event)" autocorrect="off" autocapitalize="off">
														</td>
													</tr>
													<tr>
														<th>Chat ID</th>
														<td>
															<input type="text" maxlength="20" class="input_15_table" id="jl_unotify_chat_id" onkeypress="return validator.isNumber(this,event);" autocorrect="off" autocapitalize="off">
														</td>
													</tr>
												</tbody>
											</table>

											<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable">
												<thead>
													<tr>
														<td colspan="2">Automatically enable any USB network device</td>
													</tr>
												</thead>
												<tbody>
													<tr>
														<th>Enabled</th>
														<td>
															<input type="radio" value="true" id="jl_usbnetwork" name="jl_usbnetwork" class="input" onchange="return handleRadioButton(this, event)">Yes
															<input type="radio" value="false" id="jl_usbnetwork" name="jl_usbnetwork" class="input" onchange="return handleRadioButton(this, event)">No
														</td>
													</tr>
												</tbody>
											</table>

											<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable">
												<thead>
													<tr>
														<td colspan="2">Check disk before mounting</td>
													</tr>
												</thead>
												<tbody>
													<tr>
														<th>Enabled</th>
														<td>
															<input type="radio" value="true" id="jl_diskcheck" name="jl_diskcheck" class="input" onchange="return handleRadioButton(this, event)">Yes
															<input type="radio" value="false" id="jl_diskcheck" name="jl_diskcheck" class="input" onchange="return handleRadioButton(this, event)">No
														</td>
													</tr>
												</tbody>
											</table>

											<div class="apply_gen">
												<input name="button" type="button" class="button_gen"
													onclick="applySettings();" value="Apply" />
											</div>

											<div>
												<table class="apply_gen">
													<tr class="apply_gen" valign="top"></tr>
												</table>
											</div>
										</td>
									</tr>
								</table>
							</td>
						</tr>
					</table>
				</td>
				<td width="10" align="center" valign="top"></td>
			</tr>
		</table>
	</form>
	<div id="footer"></div>
</body>
</html>
