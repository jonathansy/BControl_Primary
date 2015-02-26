function device = ZaberOpen(s, varargin)
% Open - Open and define a Zaber root object with all necessary parameters.
%
% inputs:
% -------
% s		... string, containing a serial port, e.g. 'COM4'
% 
% returns:
% --------
% ret	... device object
%
%-file history-------------------------------------------------------------
% 21.04.2012: initial creation (D.Hofer)
% 16.01.2013: s may either be a string, a serial object or a full zaber object
%--------------------------------------------------------------------------

p = inputParser;
addRequired(p, 'serialPort', @(x) ischar(x) || isa(x,'serial') || isa(x.serialPort,'serial'));
addParamValue(p, 'debugLevel', 0, @(x) isnumeric(x) && isscalar(x));
addParamValue(p, 'Timeout', 1, @(x) isnumeric(x) && isscalar(x));
addParamValue(p, 'flushTimeout', 0.2, @(x) isnumeric(x) && isscalar(x));
parse(p, s, varargin{:});

% close the serial port if open and reconfigure it
if ischar(p.Results.serialPort)
	s = serial(p.Results.serialPort);
elseif isa(p.Results.serialPort,'serial')
	s = p.Results.serialPort;
	fclose(s);
else
	s = p.Results.serialPort.serialPort;
	fclose(s);
end

set(s, 'Baudrate', 9600);
set(s, 'DataBits', 8);
set(s, 'Parity', 'none');
set(s, 'StopBits', 1);
set(s, 'Terminator', 'LF');
set(s, 'FlowControl', 'none');
set(s, 'Timeout', p.Results.Timeout);

% define sets of parameters for a list of devices, their device number
% corresponds with their array index

device.serialPort = s;				% the serial port object
device.time = tic;					% start of lifetime

% wait time to discard data
device.flushTimeOut =  p.Results.flushTimeout;			

device.devNumbers = [];				% device numbers
device.microSteps = [];				% microsteps per full step
device.microStepSize = [];			% movement per microstep
device.defaultMicroStepSize = [];	% max. movement of all stages
device.maxPosition = [];			% max. position (length)
device.maxSpeed = [];				% max. speed
device.devNames = {};				% device names
device.nrOfDevices = 0;				% number of devices found
device.isTranslationStage = [];		% boolean flag indicating stages
device.aliases = [];				% alias numbers
device.isInitialized = false;		% boolean flag indicating init is done

% debug level, default 0, warnings 1
device.debugLevel = p.Results.debugLevel;				

% (re)open the serial port and search for devices
fopen(s); 
device = ZaberUpdateDeviceList(device);

% possible commands, settings and errors
device.commands = {'Reset', 0, 'Ignored', 'Command', 'None';...
    'Home', 1, 'Ignored', 'Command', 'Final position (in this case 0)';...
    'Renumber', 2, 'Ignored', 'Command', 'Device Id';...
    'Move Tracking', 8, 'n/a', 'Reply', 'Tracking Position';...
    'Limit Active', 9, 'n/a', 'Reply', 'Final Position';...
    'Manual Move Tracking', 10, 'n/a', 'Reply', 'Tracking Position';...
    'Store Current Position', 16, 'Address', 'Command', 'Address';...
    'Return Stored Position', 17, 'Address', 'Command', 'Stored Position';...
    'Move To Stored Position', 18, 'Address', 'Command', 'Final Position';...
    'Move Absolute', 20, 'Absolute Position', 'Command', 'Final Position';...
    'Move Relative', 21, 'Relative Position', 'Command', 'Final Position';...
    'Move At Constant Speed', 22, 'Speed', 'Command', 'Speed';...
    'Stop', 23, 'Ignored', 'Command', 'Final Position';...
    'Read Or Write Memory', 35, 'Data', 'Command', 'Data';...
    'Restore Settings', 36, 'Peripheral Id', 'Command', 'Peripheral Id';...
    'Set Microstep Resolution', 37, 'Microsteps', 'Setting', 'Microsteps';...
    'Set Running Current', 38, 'Value', 'Setting', 'Value';...
    'Set Hold Current', 39, 'Value', 'Setting', 'Value';...
    'Set Device Mode', 40, 'Mode', 'Setting', 'Mode';...
    'Set Target Speed', 42, 'Speed', 'Setting', 'Speed';...
    'Set Acceleration', 43, 'Acceleration', 'Setting', 'Acceleration';...
    'Set Maximum Position', 44, 'Range', 'Setting', 'Range';...
    'Set Current Position', 45, 'New Position', 'Setting', 'New Position';...
    'Set Maximum Relative Move', 46, 'Range', 'Setting', 'Range';...
    'Set Home Offset', 47, 'Offset', 'Setting', 'Offset';...
    'Set Alias Number', 48, 'Alias Number', 'Setting', 'Alias Number';...
    'Set Lock State', 49, 'Lock Status', 'Command', 'Lock Status';...
    'Return Device Id', 50, 'Ignored', 'Read-Only Setting', 'Device Id';...
    'Return Firmware Version', 51, 'Ignored', 'Read-Only Setting', 'Version';...
    'Return Power Supply Voltage', 52, 'Ignored', 'Read-Only Setting', 'Voltage';...
    'Return Setting', 53, 'Setting Number', 'Command', 'Setting Value';...
    'Return Status', 54, 'Ignored', 'Read-Only Setting', 'Status';...
    'Echo Data', 55, 'Data', 'Command', 'Data';...
    'Return Current Position', 60, 'Ignored', 'Read-Only Setting', 'Position';...
    'Error', 255, 'n/a', 'Reply', 'Error Code'};

device.settings = {'bit_0', 1, 'Disable Auto-reply', 'A value of 1 disables ALL replies except those to �return� commands). The default value is 0 on all devices.';...
    'bit_1', 2, 'Enable Anti-backlash Routine','A value of 1 enables anti-backlash. On negative moves (retracting), the device will overshoot the desired position by 640 microsteps (assuming 64 microsteps/step), reverse direction and approach the requested position from below. On positive moves (extending), the device behaves normally. Care must be taken not to crash the moving payload into a fixed object due to the 640 microsteps overshoot on negative moves. The default value is 0 on all devices. See note on anti-backlash and anti-sticktion below.';...
    'bit_2', 4, 'Enable Anti-sticktion Routine', 'A value of 1 enables the anti-sticktion routine. On moves less than 640 microsteps (assuming 64 microsteps/step), the device will first retract to a position 640 microsteps less than the requested position and approach the requested position from below. Care must be taken not to crash the moving payload into a fixed object due to the 640 microsteps negative move. The default value is 0 on all devices. See section on anti-backlash and anti-sticktion below this table.';...
    'bit_3', 8, 'Disable Potentiometer', 'A value of 1 disables the potentiometer preventing manual adjustment of the device. The default value is 0 on all devices.';...
    'bit_4', 16, 'Enable Move Tracking', 'A value of 1 enables the Move Tracking response during move commands. The device will return its position periodically (every 0.25 sec) when a move command is executed. The Disable Auto-Reply option above takes precedence over this option. The default value is 0 on all devices. Before firmware version 5.14, only Move at Constant Speed commands could generate tracking responses, now all move commands can.';...
    'bit_5', 32, 'Disable Manual Move Tracking', 'A value of 1 disables the Manual Move Tracking response during manual moves. The Disable Auto-Reply option above takes precedence over this option. The default value is 0 on all devices.';...
    'bit_6', 64, 'Enable Message Ids', 'A value of 1 enables Message Ids. In this mode of communication, only bytes 3 through 5 are used for data. Byte 6 is used as an Id byte that the user can set to any value they wish. It will be returned unchanged in the reply. Message Ids allow the users application to monitor communication packets individually to implement error detection and recovery. The default value is 0 on all devices. Prior to firmware version 5.06, this feature was called "Virtual Channels Mode" and did not behave reliably. We do not recommend enabling this mode of communications unless you have firmware version 5.06 or later.';...
    'bit_7', 128, 'Home Status', 'This bit is set to 0 automatically on power-up or reset. It is set automatically when the device is homed or when the position is set using command #45. It can be used to detect if a device has a valid position reference. It can also be set or cleared by the user.';...
    'bit_8', 256, 'Disable Auto-Home', 'A value of 1 disables auto-home checking. Checking for trigger of home sensor is only done when home command is issued. This allows rotational devices to move multiple revolutions without re-triggering the home sensor.';...
    'bit_9', 512, 'Reverse Potentiometer', 'A value of 1 reverses the direction of the travel when the potentiometer is used to control the device. This mode bit was introduced in firmware version 5.06. Prior to that it was not used.';...
    'bit_10', 1024, 'Reserved', '';...
    'bit_11', 2048, 'Enable Circular Phase Microstepping', 'Square phase microstepping is employed by default. A value of 1 enables circular phase microstepping mode. The differences are:\r\n Circular Phase: constant torque, smoothest operation, better microstep accuracy, only 70% torque (and lower power consumption); \r\n Square Phase: non constant torque, less smooth operation, poorer microstep accuracy, 100% torque achieved (and higher power consumption)';...
    'bit_12', 4096, 'Reserved', '';...
    'bit_13', 8192, 'Reserved', '';...
    'bit_14', 16384, 'Disable Power LED', 'A value of 1 turns off the green power LED. It will still blink briefly, immediately after powerup.';...
    'bit_15', 32768, 'Disable Serial LED', 'A value of 1 turns off the yellow serial LED.'};

device.errors = { 1, 'Cannot Home', 'Home - Device has traveled a long distance without triggering the home sensor. Device may be stalling or slipping.';...
     2, 'Device Number Invalid', 'Renumbering data out of range. Data (Device number) must be between 1 and 254 inclusive.';...
     14, 'Voltage Low', 'Power supply voltage too low.';...
     15, 'Voltage High', 'Power supply voltage too high.';...
     18, 'Stored Position Invalid', 'The position stored in the requested register is no longer valid. This is probably because the maximum range was reduced.';...
     20, 'Absolute Position Invalid', 'Move Absolute - Target position out of range.';...
     21, 'Relative Position Invalid', 'Move Relative - Target position out of range.';...
     22, 'Velocity Invalid', 'Constant velocity move. Velocity out of range.';...
     36, 'Peripheral Id Invalid', 'Restore Settings - peripheral id is invalid. Please use one of the peripheral ids listed in the user manual, or 0 for default.';...
     37, 'Resolution Invalid', 'Invalid microstep resolution. Resolution may only be 1, 2, 4, 8, 16, 32, 64, 128.';...
     38, 'Run Current Invalid', 'Run current out of range. See command 38 for allowable values.';...
     39, 'Hold Current Invalid', 'Hold current out of range. See command 39 for allowable values.';...
     40, 'Mode Invalid', 'Set Device Mode - one or more of the mode bits is invalid.';...
     41, 'Home Speed Invalid', 'Home speed out of range. The range of home speed is determined by the resolution.';...
     42, 'Speed Invalid', 'Target speed out of range. The range of target speed is determined by the resolution.';...
     43, 'Acceleration Invalid', 'Target acceleration out of range. The range of target acceleration is determined by the resolution.';...
     44, 'Maximum Range Invalid', 'The maximum range may only be set between 1 and the resolution limit of the stepper controller, which is 16,777,215.';...
     45, 'Current Position Invalid', 'Current position out of range. Current position must be between 0 and the maximum range.';...
     46, 'Maximum Relative Move Invalid', 'Max relative move out of range. Must be between 0 and 16,777,215.';...
     47, 'Offset Invalid', 'Home offset out of range. Home offset must be between 0 and maximum range.';...
     48, 'Alias Invalid', 'Alias out of range. Alias must be between 0 and 254 inclusive.';...
     49, 'Lock State Invalid', 'Lock state must be 1 (locked) or 0 (unlocked).';...
     50, 'Device Id Unknown', 'The device id is not included in the firmware''s list.';...
     53, 'Setting Invalid', 'Return Setting - data entered is not a valid setting command number. Valid setting command numbers are the command numbers of any "Set ..." instructions.';...
     64, 'Command Invalid', 'Command number not valid in this firmware version.';...
     255, 'Busy', 'Another command is executing and cannot be pre-empted. Either stop the previous command or wait until it finishes before trying again.';...
     1600, 'Save Position Invalid', 'Save Current Position register out of range (must be 0-15).';...
     1601, 'Save Position Not Homed', 'Save Current Position is not allowed unless the device has been homed.';...
     1700, 'Return Position Invalid', 'Return Stored Position register out of range (must be 0-15).';...
     1800, 'Move Position Invalid', 'Move to Stored Position register out of range (must be 0-15).';...
     1801, 'Move Position Not Homed', 'Move to Stored Position is not allowed unless the device has been homed.';...
     2146, 'Relative Position Limited', 'Move Relative (command 20) exceeded maximum relative move range. Either move a shorter distance, or change the maximum relative move (command 46).';...
     3600, 'Settings Locked', 'Must clear Lock State (command 49) first. See the Set Lock State command for details.';...
     4008, 'Disable Auto Home Invalid', 'Set Device Mode - this is a linear actuator; Disable Auto Home is used for rotary actuators only.';...
     4010, 'Bit 10 Invalid', 'Set Device Mode - bit 10 is reserved and must be 0.';...
     4012, 'Home Switch Invalid', 'Set Device Mode - this device has integrated home sensor with preset polarity; mode bit 12 cannot be changed by the user.';...
     4013, 'Bit 13 Invalid', 'Set Device Mode - bit 13 is reserved and must be 0.'};