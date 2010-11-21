--[[-----------------------------------------------------------------------

    $Id$

    $HeadURL$

    Copyright (c) 2010; Mark Rogaski.

    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

        * Redistributions of source code must retain the above copyright
          notice, this list of conditions and the following disclaimer.

        * Redistributions in binary form must reproduce the above
          copyright notice, this list of conditions and the following
          disclaimer in the documentation and/or other materials provided
          with the distribution.

        * Neither the name of the copyright holder nor the names of any
          contributors may be used to endorse or promote products derived
          from this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
    A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
    OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
    SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
    LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
    DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
    THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
    OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


--]]-----------------------------------------------------------------------

--[[-----------------------------------------------------------------------

Global Variables

--]]-----------------------------------------------------------------------

--
-- Add-on metadata
--

local gwVersion			= GetAddOnMetadata('GreenWall', 'Version');


--
-- Player variables
--

local gwPlayerName 		= UnitName('Player');
local gwGuildName		= GetGuildInfo('Player'); 
local gwPlayerLanguage	= GetDefaultLanguage('Player');


--
-- Co-guild variables
--

local gwConfigString	= '';
local gwChannelName 	= nil;
local gwChannelNumber	= 0;
local gwChannelPass 	= nil;
local gwContainerId		= nil;
local gwPeerTable		= {};


--
-- State variables
--

local gwFlagOwner		= false;
local gwFlagModerator	= false;
local gwFlagHandoff		= false;
local gwAddonLoaded		= false;
local gwRosterLoaded	= false;


--
-- Timers and thresholds
--

local gwHandoffTimeout	= 30;
local gwHandoffTimer	= nil;

local gwReloadHolddown	= 180;
local gwLastReload		= 0;


--
-- Tables external to functions
--

local gwChannelTable	= {};
local gwChatWindowTable = {};
local gwFrameTable		= {};


--[[-----------------------------------------------------------------------

Convenience Functions

--]]-----------------------------------------------------------------------

local function GwWrite(msg)

	DEFAULT_CHAT_FRAME:AddMessage('|cffabd473GreenWall:|r ' .. msg);

end


local function GwError(msg)

	DEFAULT_CHAT_FRAME:AddMessage('|cffabd473GreenWall:|r |cffff6000[ERROR] ' .. msg);

end


local function GwDebug(level, msg)

	if GreenWall ~= nil then
		if level <= GreenWall.debugLevel then
			DEFAULT_CHAT_FRAME:AddMessage(
					format('|cffabd473GreenWall:|r |cff778899[DEBUG/%d] %s|r', level, msg));
		end
	end
	
end


local function GwIsConnected()

	--
	-- Refresh the list of chat frames with guild chat
	--
	table.wipe(gwFrameTable);
	for i = 1, 10 do
		local ChatWindowTable = { GetChatWindowMessages(i) }
    	for _, v in ipairs(ChatWindowTable) do
       		if v == 'GUILD' then
       			tinsert(gwFrameTable, i)
       		end
    	end 
   	end
	
	--
	-- Look for an existing connection
	--
	gwChannelList = { GetChannelList() };
	for i, v in ipairs(gwChannelList) do
		if v == gwChannelName then
			return true;
		end
	end

	return false;
			
end


local function GwIsOfficer(target)

	local rank;
	local ochat = false;
	
	if target == nil then
		target = 'Player';
	end
	_, _, rank = GetGuildInfo(target);
	
	GuildControlSetRank(rank);
	_, _, ochat = GuildControlGetRankFlags();
	
	if ochat then
		GwDebug(5, format('%s is rank %d and can see ochat', target, rank));
	else
		GwDebug(5, format('%s is rank %d and cannot see ochat', target, rank));
	end
	
	return ochat;

end


local function GwLeaveChannel()

	LeaveChannelByName(gwChannelName);
	GwDebug(1, format('left channel %s (%d)', gwChannelName, gwChannelNumber));
	gwChannelNumber	= 0;

end


local function GwJoinChannel(name, pass, container)

	if GwIsConnected() then
		GwLeaveChannel()
	end
	
	if name then
		--
		-- Open the communication link
		--
		local id, altName = JoinTemporaryChannel(name, pass);
		
		if sysName then
			gwChannelName = altName;
		else
			gwChannelName = name;
		end
		
		if not id then

			GwError(format('cannot create communication channel: %s', name));

		else
	
			gwChannelNumber = GetChannelName(gwChannelName);
			gwContainerId = container;
			GwDebug(1, format('joined channel %s (%d)', gwChannelName, gwChannelNumber));

			--
			-- Check for default permissions
			--
			local _, _, _, _, count = GetChannelDisplayInfo(gwChannelNumber);
			if count == 1 then
				gwFlagOwner = true;
			end
			
			--
			-- Hide the channel
			--
			for i = 1, 10 do
				gwChatWindowTable = { GetChatWindowMessages(i) };
				for j, v in ipairs(gwChatWindowTable) do
					if v == gwChannelName then
						local frame = format('ChatFrame%d', i);
						if _G[frame] then
							GwDebug(2, format('hiding channel %s (%d) in %s', 
									gwChannelName, gwChannelNumber, frame));
							ChatFrame_RemoveChannel(frame, gwChannelName);
						end
					end
				end
			end
		
		end
		
	end
	
end


local function GwRefreshComms()

	local info = GetGuildInfoText();
	
	if info == '' then

		GwDebug(2, 'Guild Info not yet available.');
		
	else	
	
		local config 	= '';
		local channel	= nil;
		local password	= nil;
		local container	= nil;
		
		-- Make sure we know which co-guild we are in.
		if gwGuildName == nil or gwGuildName == '' then
			gwGuildName = GetGuildInfo('Player');
		end
		
		-- We will rebuild the list of peer container guilds
		wipe(gwPeerTable);

		for buffer in gmatch(info, 'GW:([^\n]+)') do
		
			if buffer ~= nil then
						
				buffer = strtrim(buffer);
				local vector = { strsplit(':', buffer) };
			
				if vector[1] == 'c' then
				
					config 		= buffer;
					channel 	= vector[2];
					password	= vector[3];
					GwDebug(2, format('channel: %s, password: %s', channel, password));
									
				elseif vector[1] == 'p' then
		
					if vector[2] == gwGuildName then
						container = vector[3];
						GwDebug(2, format('container: %s (%s)', gwGuildName, container));
					else 
						gwPeerTable[vector[2]] = vector[3];
						GwDebug(2, format('peer: %s (%s)', vector[2], vector[3]));
					end
					
				end
		
			end
	
		end	
		
		--
		-- Update the top-level variables
		--
		local confUpdate = false;
		if config ~= gwConfigString then
			gwConfigString 	= config;
			confUpdate = true;
		end
		gwChannelName 	= channel;
		gwChannelPass 	= password;
		gwContainerId 	= container;
		
		--
		-- Reconnect if necessary
		--
		if not GwIsConnected() or confUpdate then
			GwDebug(2, 'client not connected.');
			GwJoinChannel(gwChannelName, gwChannelPass, gwContainerId);
		else
			GwDebug(2, 'client already connected.');
		end

	end

end


local function GwSendConfederationMsg(type, message)

	GwDebug(5, format('conf_msg type=%s, message=%s', type, message));

	local opcode;
	
	if type == nil then
		GwDebug(2, 'missing arguments to GwSendConfederationMsg().');
		return;
	elseif type == 'chat' then
		opcode = 'C';
	elseif type == 'achievement' then
		opcode = 'A';
	elseif type == 'notice' then
		opcode = 'N';
	elseif type == 'request' then
		opcode = 'R';
	else
		GwDebug(2, format('unknown message type: %s', type));
		return;
	end
	
	if message == nil then
		message = '';
	end
	
	local payload = strsub(strjoin('#', opcode, gwContainerId, '', message), 1, 255);
	GwDebug(3, format('Tx<%d, *, %s>: %s', gwChannelNumber, gwPlayerName, payload));
	SendChatMessage(payload , "CHANNEL", nil, gwChannelNumber); 

end


local function GwSendContainerMsg(type, message)

	GwDebug(5, format('cont_msg type=%s, message=%s', type, message));

	local opcode;
	
	if type == nil then
		GwDebug(2, 'missing arguments to GwSendContainerMsg().');
		return;
	elseif type == 'request' then
		opcode = 'C';
	elseif type == 'response' then
		opcode = 'R';
	elseif type == 'info' then
		opcode = 'I';
	else
		GwDebug(2, format('unknown message type: %s', type));
		return;
	end

	local payload = strsub(strjoin('#', opcode, message), 1, 255);
	GwDebug(3, format('Tx<ADDON/GUILD, *, %s>: %s', gwPlayerName, payload));
	SendAddonMessage('GreenWall', payload, 'GUILD');
	
end


local function GwForceReload()
	if GwIsConnected() then
		GwSendConfederationMsg('request', 'reload');
	end 
end


--[[-----------------------------------------------------------------------

Slash Command Handler

--]]-----------------------------------------------------------------------

local function GwSlashCmd(message, editbox)

	--
	-- Initialize the saved variables
	--
	if GreenWall == nil then
		GreenWall = {
			version	= gwVersion,
			debugLevel = 0
		};
	end

	GreenWall.version = gwVersion;

	--
	-- Parse the command
	--
	local command, argstr = message:match('^(%S*)%s*(.*)');
	command = command:lower();
	
	GwDebug(4, format('command: %s, args: %s', command, argstr));
	
	if command == 'debug' then
	
		local level = argstr:match('^(%d+)%s*$');
		if level ~= nil then
			GreenWall.debugLevel = level + 0; -- Lua typing stinks, gotta coerce an integer.
			GwWrite(format('Set debugging level to %d.', GreenWall.debugLevel));
		else
			GwError(format('Invalid argument: %s', argstr));
		end
		
	elseif command == 'reload' then
	
		GwForceReload();
	
	else
	
		GwError(format('Unknown command: %s', command));

	end

end


--[[-----------------------------------------------------------------------

Initialization

--]]-----------------------------------------------------------------------

function GreenWall_OnLoad(self)

	-- 
	-- Set up slash commands
	--
	SLASH_GREENWALL1 = '/greenwall';
	SLASH_GREENWALL2 = '/gw';	
	SlashCmdList['GREENWALL'] = GwSlashCmd;
	
	--
    -- Trap the events we are interested in
    --
    self:RegisterEvent('ADDON_LOADED');
    self:RegisterEvent('CHANNEL_UI_UPDATE');
    self:RegisterEvent('CHAT_MSG_ADDON');
    self:RegisterEvent('CHAT_MSG_CHANNEL');
	self:RegisterEvent('CHAT_MSG_CHANNEL_JOIN');
	self:RegisterEvent('CHAT_MSG_CHANNEL_LEAVE');
    self:RegisterEvent('CHAT_MSG_CHANNEL_NOTICE_USER');
    self:RegisterEvent('CHAT_MSG_GUILD');
    self:RegisterEvent('CHAT_MSG_GUILD_ACHIEVEMENT');
	self:RegisterEvent('GUILD_ROSTER_UPDATE');
	self:RegisterEvent('PLAYER_ENTERING_WORLD');
	self:RegisterEvent('PLAYER_GUILD_UPDATE');
    
end


--[[-----------------------------------------------------------------------

Frame Event Functions

--]]-----------------------------------------------------------------------

function GreenWall_OnEvent(self, event, ...)

	GwDebug(4, format('event: %s', event));

	--
	-- Event switch
	--
	if event == 'ADDON_LOADED' and select(1, ...) == 'GreenWall' then
		
		gwAddonLoaded = true;
		GwWrite(format('v%s loaded.', gwVersion));			
		
	elseif event == 'CHANNEL_UI_UPDATE' then
	
		if gwPlayerGuild ~= nil and not GwIsConnected() then
			-- GwJoinChannel(gwChannelName, gwChannelPass);
			GwRefreshComms();
		end
	
	elseif event == 'PLAYER_ENTERING_WORLD' then

		GuildRoster();

	elseif event == 'GUILD_ROSTER_UPDATE' then
	
		if not gwRosterLoaded then
			GwRefreshComms();
		end
		
		if GwIsConnected() then
			gwRosterLoaded = true;
		end

	elseif event == 'PLAYER_GUILD_UPDATE' then
	
		gwPlayerGuild = GetGuildInfo('Player');
		if gwPlayerGuild ~= nil then
			GuildRoster();
			GwRefreshComms();
		elseif GwIsConnected() then
			GwLeaveChannel();
		end

	elseif event == 'CHAT_MSG_GUILD' then
	
		local message, sender, language, _, _, flags, _, chanNum = select(1, ...);
		if sender == gwPlayerName then
			GwSendConfederationMsg('chat', message);		
		end
	
	elseif event == 'CHAT_MSG_GUILD_ACHIEVEMENT' then
	
		local message, sender, _, _, _, flags, _, chanNum = select(1, ...);
		if sender == gwPlayerName then
			GwSendConfederationMsg('achievement', message);
		end
	
	elseif event == 'CHAT_MSG_CHANNEL' then
	
		local payload, sender, language, _, _, flags, _, 
				chanNum, _, _, counter, guid = select(1, ...);
		
		GwDebug(3, format('Rx<%d, %s>: %s', chanNum, sender, payload));
		
		if chanNum == gwChannelNumber then
		
			local opcode, container, _, message = payload:match('^(%a)#(%w+)#([^#]*)#(.*)');
			
			if opcode == 'C' and sender ~= gwPlayerName and container ~= gwContainerId then
		
				--
				-- Incoming chat message
				--
				
				for i, v in ipairs(gwFrameTable) do
					local frame = 'ChatFrame' .. v;
					if _G[frame] then
						GwDebug(3, format('Tx<GUILD, *, %s>: %s', sender, message));
						ChatFrame_MessageEventHandler(
								_G[frame], 
								'CHAT_MSG_GUILD', 
								message, 
								sender, 
								language, 
								'', 
								'', 
								'', 
								0, 
								0, 
								'', 
								0, 
								counter, 
								guid
							);
					end
				end
			
			elseif opcode == 'A' and sender ~= gwPlayerName and container ~= gwContainerId then
			
				--
				-- Incoming achievement spam
				--
				
				for i, v in ipairs(gwFrameTable) do
					local frame = 'ChatFrame' .. v;
					if _G[frame] then
						GwDebug(3, 
								format('Tx<GUILD_ACHIEVEMENT, *, %s>: %s', sender, message));
						ChatFrame_MessageEventHandler(
								_G[frame], 
								'CHAT_MSG_GUILD_ACHIEVEMENT',
								message,
								sender,
								language, 
								'',
								'', 
								'', 
								0, 
								0, 
								'', 
								0, 
								counter, 
								guid
							);
					end
				end
			
			elseif opcode == 'R' then
			
				--
				-- Incoming request
				--
				
				if message:match('^reload(%w.*)?$') then 
					local diff = time() - gwLastReload;
					if diff >= gwReloadHolddown then
						GwRefreshComms();
						gwLastReload = time();
					end
				end
			
			end
		
		end
		
	elseif event == 'CHAT_MSG_CHANNEL_JOIN' then
	
		local name = select(2, ...);
		local chanNum = select(8, ...);
		
		if chanNum == gwChannelNumber then
		
			local oneOfUs = true;  -- Benefit of the doubt
			local guild = GetGuildInfo(name);
			if gwFlagOwner or gwFlagModerator then
				if gwPeerTable[guild] == nil then
					oneOfUs = false;
				end
				GwDebug(5, format('name=%s, guild=%s', name, guild));
			end

			if not oneOfUs then
			else
				-- ChannelBan(gwChannelName, name);
				ChannelKick(gwChannelName, name);
				GwSendConfederationMsg('notice', 
						format('removed %s (%s), not in a co-guild.', name, guild)); 
			end			

			--
			-- Advertise the member status
			--
			DEFAULT_CHAT_FRAME:AddMessage(format(ERR_FRIEND_ONLINE_SS, name, name),
					1.0, 1.0, 0.0, GetChatTypeIndex('CHAT_MSG_SYSTEM'));

		end
			
	elseif event == 'CHAT_MSG_CHANNEL_LEAVE' then
	
		local name = select(2, ...);
		local chanNum = select(8, ...);
		
		if chanNum == gwChannelNumber then

			--
			-- Advertise the member status
			--
			DEFAULT_CHAT_FRAME:AddMessage(format(ERR_FRIEND_OFFLINE_S, name),
					1.0, 1.0, 0.0, GetChatTypeIndex('CHAT_MSG_SYSTEM'));

		end

	elseif event == 'CHAT_MSG_CHANNEL_NOTICE_USER' then
	
		local message, target, _, _, actor, _, _, chanNum = select(1, ...);
	
		GwDebug(5, format('event=%s, message=%s, target=%s, actor=%s, chanNum=%s',
				event, message, target, actor, chanNum));
	
		--
		-- Set the appropriate flags
		--
		if message == 'OWNER_CHANGED' then
			if target == gwPlayerName then
				gwFlagOwner = true;
			else
				gwFlagOwner = false;
			end
		elseif message == 'SET_MODERATOR' and target == gwPlayerName then
			gwFlagModerator = true;
		elseif message == 'UNSET_MODERATOR' and target == gwPlayerName then
			gwFlagModerator = false;
		end
	
		if (message == 'OWNER_CHANGED' or message == 'SET_MODERATOR') 
				and target == gwPlayerName then
			if not GwIsOfficer() then
				-- Set a time to drop moderator status
				gwHandoffTimer = time() + gwHandoffTimeout;
				gwFlagHandoff = false;
			end
			-- Query the members of the container guild for officers
			GwSendContainerMsg('request', 'officer');
		end
		
	elseif event == 'CHAT_MSG_ADDON' then
	
		local prefix, message, dist, sender = select(1, ...);
		
		GwDebug(5, format('event=%s, prefix=%s, sender=%s, dist=%s, message=%s',
				event, prefix, sender, dist, message));
		
		GwDebug(3, format('Rx<ADDON(GreenWall), %s>: %s', sender, message));
		
		if prefix == 'GreenWall' and dist == 'GUILD' and sender ~= gwPlayerName then
		
			local type, command = strsplit('#', message);
			
			GwDebug(5, format('type=%s, command=%s', type, command));
			
			if type == 'C' then
			
				if command == 'officer' then
					if GwIsOfficer() then
						-- Let 'em know you have the authoritay!
						GwSendContainerMsg('response', 'officer');
					end
				end
			
			elseif type == 'R' then
			
				if command == 'officer' then
					if gwFlagModerator or gwFlagOwner then
						-- Verify the claim
						if GwIsOfficer(sender) then
							if gwFlagOwner then
								GwDebug(1, format('Granting owner status to $s.', sender));
								SetChannelOwner(gwChannelName, sender);
							else
								GwDebug(1, format('Granting moderator status to $s.', sender));
								ChannelModerator(gwChannelName, sender);
							end
							gwFlagHandoff = true;
						end
					end
				end
			
			end
			
		end
		
	end

	--
	-- Take care of our lazy timers
	--
	if gwHandoffTimer ~= nil then
		if gwHandoffTimer <= time() then
			-- Abdicate moderator status
			GwDebug(1, 'Handoff timer expired, releasing moderator status.');
			ChannelUnmoderator(gwChannelName, gwPlayerName);
			gwHandoffTimer = nil;
		end
	end

end


--[[-----------------------------------------------------------------------

END

--]]-----------------------------------------------------------------------