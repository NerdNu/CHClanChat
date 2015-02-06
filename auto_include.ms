
/*
 * DB Schema:
 * clanchat.channels - An array of all the channels
 * clanchat.channels.<channel> - An array of all the channel infos:
 * 				- managers: array of managers
 *				- invites: array of invited, but not yet accepted players
 *				- members: array of players in this channel (including managers and the owner)
 *				- bulletins: array of channel announcements
 *				- owner: The owner's name
 *				- color: the color of the channel name
 *				- textcolor: the color of the channel text
 *				- alertcolor: the color of channel alert text
 *				- flags: list of channel flags. 
 *					 Secret channels you must be a member to view other members
 *					 Public channels anyone can join
 * clanchat.players - An associative array of all the players (key) with their player infos:
 *				- lastReceived: The last channel they receieved a message from
 * 				- default: Their default channel name
 *				- subscribed: The channels they will receive bulletins from on login
 * 				- channels: A list of this players channels
 */

/*
 * Public methods
 */

/**
 * Creates a new channel. The current player is set as the owner,
 * and this will die if the channel already exists.
 */
proc(_cc_create_channel, @channel,
	@channel = to_lower(@channel)
	@channels = _cc_get_value('clanchat.channels', array())
	if(array_contains(@channels, @channel)){
		msg(color(RED).'That channel already exists. If you would like to join the channel, speak with the owner')
		die()
	} else {
		# Success, the channel is available! But first, make sure it's properly formatted.
		if(!reg_count('^(?i)[a-z0-9_]+$', @channel)){
			die(color(RED).'Oops! That channel name isn\'t valid. You can only have letters and numbers in your channel name.')
		}	
		if(length(@channel) > 16){
			die(color(RED).'Oops! Please limit your channel name length to 16 characters!')
		}
		array_push(@channels, @channel)
		store_value('clanchat.channels', @channels)
		# Set up the channel struct
		@uuid = _get_puuid(player())
		@channelInfo = array(
			managers: array(),
			invites: array(),
			members: array(@uuid),
			bulletins: array(),
			owner: @uuid,
			color: 'BLUE',
			textcolor: 'GRAY',
			alertcolor: 'GRAY',
			flags: array(
				public: false,
				secret: false
			)
		)
		store_value('clanchat.channels.'.@channel, @channelInfo)
		@playerInfo = _cc_get_player_info(@uuid)
		array_push(@playerInfo['channels'], @channel)
		array_push(@playerInfo['subscribed'], @channel)
		msg(color(BLUE).'You will receive bulletins from this channel on login. To unsubscribe run /clanchat unsubscribe '.@channel)
		_cc_save_player_info(@uuid, @playerInfo)
		_cc_set_default(@channel)
		die(color(LIGHT_PURPLE).'Channel created!')
	}
)

proc(_cc_delete_channel, @channel, 
	@channel = to_lower(@channel)
	@channelInfo = _cc_get_channel_info(@channel)
	@uuid = _get_puuid(player())
	#make sure the player is the current owner
	if ((@uuid != @channelInfo['owner']) && (strip_colors(player()) != '~console')) {
		die(color(RED).'Only the owner can delete a channel')
	}
	msg(color(RED).'This command is irreversible. Your channel and all associated data WILL Be lost!')
	msg(color(BLUE).'Type "/clanchat confirm delete" to confirm you actually want to delete your channel.')
	@player = player()
	bind(player_command, null, array(player: @player), @event, @channel, @channelInfo, 
		if(@event['command'] == '/clanchat confirm delete') {
			@members = @channelInfo['members']
			foreach(@members, @member,
				@playerInfo = _cc_get_player_info(@member)
				array_remove_values(@playerInfo['channels'], @channel)
				array_remove_values(@playerInfo['subscribed'], @channel)
				_cc_save_player_info(@member, @playerInfo)
			)
			@channels = get_value('clanchat.channels')
			array_remove_values(@channels, @channel)
			store_value('clanchat.channels', @channels)

			clear_value('clanchat.channels.'.@channel)
			msg(color(RED).'Your channel was deleted!')
			#delete channel
			unbind();
		} else {
			msg(color(RED).'Your channel was not deleted.')
			unbind();
		}
	)
)

/**
 * Sets the owner in @channel to @newowner
 * player() must be current owner
 */
proc(_cc_change_owner, @channel, @newOwner,
	@channel = to_lower(@channel)
	@channelInfo = _cc_get_channel_info(@channel)
	#make sure the player is the current owner
	@uuid = _get_puuid(player())
	if ((@uuid != @channelInfo['owner']) && (strip_colors(player()) != '~console')){
		die(color(RED).'Only the owner can set a new owner for the channel')
	}
	# set the new owner, add the old owner to the managers list
	@uuid = _get_puuid(@newOwner)
	@channelInfo['owner'] = @uuid
	_cc_save_channel_info(@channel, @channelInfo)
	die(color(AQUA).'You have relinquished ownership on '.@channel.' to '.@newOwner)
)

/**
 * Changes color of @channel to @color
 * @key is either color or textcolor, description is either color or text color
 */
proc(_cc_set_channel_color, @channel, @color, @key, @description,
	@colors = array(BLACK, DARK_BLUE, DARK_GREEN, DARK_AQUA, DARK_RED, DARK_PURPLE, GOLD, GRAY, DARK_GRAY, 
		BLUE, GREEN, AQUA, RED, LIGHT_PURPLE, YELLOW, WHITE)
	@channel = to_lower(@channel)
	@channelInfo = _cc_get_channel_info(@channel)
	_cc_assert_manager(@channelInfo)
	@color = to_upper(@color)
	if(array_contains(@colors, @color)){
		@channelInfo[@key] = @color
		_cc_save_channel_info(@channel, @channelInfo)
		die(color(BLUE).'Channel '.@description.' changed to '.color(@color).@color.'!')
	} else {
		@output = array()
		foreach(@colors, @color,
			array_push(@output, color(@color).@color)
		)
		die('Only one of the following can be set as the channel '.@description.':'.array_implode(@output, color(WHITE).', '))
	}
)

/**
 * Messages out a list of all the players in the given channel
 */
proc(_cc_print_members, @channel,
	@uuid = _get_puuid(player())
	@playerInfo = _cc_get_player_info(@uuid)
	@channel = to_lower(@channel)
	@channelInfo = _cc_get_channel_info(@channel)
	@members = @channelInfo['members']
	if(@channelInfo['flags']['secret']){
		if (!array_contains(@members, @uuid) && (player() != ~console)) {
			die(color(RED).'This channel is secret. You must be a member of the channel to see who is in the channel')
		}
	}
	@online = array()
	@offline = array()
	foreach(@members, @member,
		@member_name = _get_username_from_uuid(@member)
		if(ponline(@member_name)){
			array_push(@online, player(@member_name))
		} else {
			array_push(@offline, @member_name)
		}
	)
	msg(color(GOLD).'Online: '._cc_format_list(@online))
	msg(color(GOLD).'Offline: '._cc_format_list(@offline))
	msg(color(BLUE).'There are '.array_size(@members).' member'.if(array_size(@members) == 1, '', 's').' in '.color(@channelInfo['color']).@channel)
)

/**
 * Invites a player into this channel. The current player must be either an owner
 * or a manager to do this.
 */
proc(_cc_invite_member, @channel, @player,
	@channel = to_lower(@channel)
	@player = to_lower(@player)
	@uuid = _get_puuid(@player)
	@channelInfo = _cc_get_channel_info(@channel)
	_cc_assert_manager(@channelInfo)
	@invites = @channelInfo['invites']
	if(!array_contains(@invites, @uuid)){
		array_push(@invites, @uuid)
		_cc_save_channel_info(@channel, @channelInfo)
		if(ponline(@player)){
			# Also inform them if they are online. If not, oh well.
			tmsg(@player, color(BLUE).'You have been invited to "'.@channel.'" by '.strip_colors(player()).'.')
			tmsg(@player, color(BLUE).'Type '.color(GRAY).'/clanchat join '.@channel.color(BLUE).' to join')
		}
		die(color(BLUE).@player.' has been invited to '.@channel)
	} else {
		die(color(BLUE).'That player was already invited, but they haven\'t accepted yet')
	}
)

/**
 * Uninvites a member that has been invited, but hasn't yet accepted.
 */
proc(_cc_uninvite_member, @channel, @player,
	@channel = to_lower(@channel)
	@player = to_lower(@player)
	@uuid = _get_puuid(@player)
	@channelInfo = _cc_get_channel_info(@channel)
	_cc_assert_manager(@channelInfo)
	@invites = @channelInfo['invites']
	if(!array_contains(@invites, @uuid)){
		die(color(RED).'That player isn\'t in the invite list.')
	} else {
		array_remove_values(@invites, @uuid)
		_cc_save_channel_info(@channel, @channelInfo)
		die(color(BLUE).'Player removed from the invite list')
	}
)

/**
 * Adds a user to the channel as a manager. Only the owner can run this.
 * The user must already be in the channel for this to work.
 */
proc(_cc_add_manager, @channel, @player,
	@channel = to_lower(@channel)
	@player = to_lower(@player)
	@uuid = _get_puuid(@player)
	@channelInfo = _cc_get_channel_info(@channel)
	if(@channelInfo['owner'] != _get_puuid(player())) {
		die(color(RED).'Only the owner may add or remove managers')
	}
	@managers = @channelInfo['managers']
	@members = @channelInfo['members']
	if(!array_contains(@members, @uuid)){
		die(color(RED).'Only members can be made managers. Invite them to the channel, and wait for them to join first.')
	} else if(array_contains(@managers, @uuid)){
		die(color(RED).@player.' is already a manager')
	} else {
		array_push(@managers, @uuid)
		if(ponline(@player)){
			tmsg(@player, color(BLUE).'You have been made a manager in '.@channel)
		}
		_cc_save_channel_info(@channel, @channelInfo)
		die(color(BLUE).@player.' added as a manager!')
	}
)

/**
 * Removes a user's manager permissions from the channel. Only the owner can
 * run this.
 */
proc(_cc_remove_manager, @channel, @player,
	@channel = to_lower(@channel)
	@player = to_lower(@player)
	@uuid = _get_puuid(@player)
	@channelInfo = _cc_get_channel_info(@channel)
	if(@channelInfo['owner'] != _get_puuid(player())) {
		die(color(RED).'Only the owner may add or remove managers')
	}
	@managers = @channelInfo['managers']
	if(array_contains(@managers, @uuid)){
		array_remove_values(@managers, @uuid)
		_cc_save_channel_info(@channel, @channelInfo)
		die(color(BLUE).'Player removed as a manager from '.@channel)
	} else {
		die(color(RED).@player.' is not a manager in '.@channel)
	}
)

/**
 * Lists managers in a channel. Owner only.
 */
proc(_cc_print_managers, @channel, 
	@channel = to_lower(@channel)
	@uuid = _get_puuid(player())
	@channelInfo = _cc_get_channel_info(@channel)
	if(@channelInfo['owner'] == @uuid){
		@online = array()
		@offline = array()
		foreach(@channelInfo['managers'], @manager,
			@managerName = _get_puuid(@manager)
			if(ponline(@managerName)){
				array_push(@online, player(@managerName))
			} else {
				array_push(@offline, @managerName)
			}
		)
	} else {
		die (color(RED).'Only owners can do that')
	}
	msg(color(GOLD).'Online: '._cc_format_list(@online))
	msg(color(GOLD).'Offline: '._cc_format_list(@offline))
)

/**
 * Removes a player from this channel. The owner cannot be removed, and managers can
 * only be removed by the owner, and normal users don't have access at all.
 */
proc(_cc_remove_member, @channel, @player,
	@channel = to_lower(@channel)
	@uuid = _get_puuid(@player)
	@channelInfo = _cc_get_channel_info(@channel)
	_cc_assert_manager(@channelInfo)
	if(@channelInfo['owner'] == @uuid){
		die(color(RED).'You cannot remove the owner from a channel!')
	}
	if(_get_puuid(player()) != @channelInfo['owner'] && array_contains(@channelInfo['managers'], @uuid)){
		die(color(RED).'Only the owner can remove a manager')
	}
	if(!array_contains(@channelInfo['members'], @uuid)) {
		die(color(RED).'That player isn\'t a member.')
	}
	# At this point, they are a manager, and we aren't trying to remove a manager
	array_remove_values(@channelInfo['members'], @uuid)
	array_remove_values(@channelInfo['managers'], @uuid)
	@playerInfo = _cc_get_player_info(@uuid)
	array_remove_values(@playerInfo['channels'], @channel)
	array_remove_values(@playerInfo['subscribed'], @channel)
	_cc_save_player_info(@uuid, @playerInfo)
	_cc_save_channel_info(@channel, @channelInfo)
	die(color(BLUE).'Member removed.')
)

/**
 * Joins a channel, if the user has been invited.
 */
proc(_cc_join_channel, @channel,
	@channel = to_lower(@channel)
	@channelInfo = _cc_get_channel_info(@channel)
	@uuid = _get_puuid(player())
	@playerInfo = _cc_get_player_info(@uuid)
	@output = array()
	if(array_contains(@playerInfo['channels'], @channel)){
		die(color(RED).'You\'re already a member of this channel!')
	}
	if(and(!array_contains_ic(@channelInfo['invites'], @uuid),!(@channelInfo['flags']['public'] ))){
		die(color(RED).'You can\'t join a non-public channel without an invite. Please speak with '.@channelInfo['owner'].' about joining')
	}
	array_remove_values(@channelInfo['invites'], @uuid)
	array_push(@channelInfo['members'], @uuid)
	array_push(@playerInfo['channels'], @channel)
	if(array_size(@playerInfo['subscribed']) == 0) {
		array_push(@playerInfo['subscribed'], @channel)
		msg(color(BLUE).'You will receive bulletins from this channel on login. To unsubscribe run /clanchat unsubscribe '.@channel)
	} else {
		msg(color(BLUE).'To receive bulletins from this channel on login, run /clanchat subscribe '.@channel)
	}
	_cc_save_player_info(@uuid, @playerInfo)
	_cc_set_default(@channel)
	_cc_save_channel_info(@channel, @channelInfo)
	msg(color(BLUE).'Type '.color(GRAY).'/c #'.@channel.' <msg>'.color(BLUE).' to say something to this channel, or just '.color(GRAY).'/c <msg>'.color(BLUE)
		.' if this is already your default channel')
	_cc_send_raw_message(@channel, color(RED).strip_colors(player()).color(BLUE).' has joined '.color(@channelInfo['color']).@channel.color(BLUE).', say hi!')
)

/**
 * Allows a user to leave the channel themselves, but otherwise works like
 * _cc_remove_member(@channel, player())
 */
proc(_cc_leave_channel, @channel,
	@channel = to_lower(@channel)
	@channelInfo = _cc_get_channel_info(@channel)
	@uuid = _get_puuid(player())
	@playerInfo = _cc_get_player_info(@uuid)

	if(!array_contains(@channelInfo['members'], @uuid)){
		die(color(RED).'You can\'t leave a channel you\'re not in')
	}

	#stop the owner from leaving his channels
	if (@channelInfo['owner'] == @uuid){
		if (array_size(@channelInfo['members']) != 1){
			die(color(RED).'The owner can\'t leave their channel unless the channel is empty. Please set someone else as owner first, or use "/clanchat delete <channel>" to remove the channel.')
		} 
	}
	array_remove_values(@channelInfo['members'], @uuid)
	array_remove_values(@playerInfo['channels'], @channel)
	array_remove_values(@playerInfo['subscribed'], @channel)
	_cc_save_player_info(@uuid, @playerInfo)
	_cc_save_channel_info(@channel, @channelInfo)
	
	#if no players are in the channel, remove it
	if (array_size(@channelInfo['members']) == 0){
		clear_value('clanchat.channels.'.@channel)
		@channels = get_value('clanchat.channels')
		array_remove_values(@channels, @channel)
		store_value('clanchat.channels', @channels)
	}		
	die(color(BLUE).'You have been removed from '.@channel)
)

/**
 * Sets the player's default channel. If this is different than the previous channel,
 * then they are sent a message telling them their default channel has changed.
 * Will not allow users to set their default channel to a channel they are not a member of.
 */
proc(_cc_set_default, @channel,
	if(player() == '~console'){
		return()
	}
	@channel = to_lower(@channel)
	@uuid = _get_puuid(player())
	@playerInfo = _cc_get_player_info(@uuid)
	@channelInfo = _cc_get_channel_info(@channel)

	if(@playerInfo['default'] != @channel){
		if (!array_contains(@playerInfo['channels'], @channel)){
			die (color(RED).'You are not a member of '.@channel.'. Please speak to '.@channelInfo['owner'].' to join')
		}
		@playerInfo['default'] = @channel
		_cc_save_player_info(@uuid, @playerInfo)
		msg(color(DARK_BLUE).'Your default channel has been changed to '.@channel)
	}
)

/**
 * Returns the player's default channel
 */
proc(_cc_get_default,
	@uuid = _get_puuid(player())
	@playerInfo = _cc_get_player_info(@uuid)
	return(@playerInfo['default'])
)

/**
 * Returns the last channel the player sent a message to
 */
proc(_cc_get_last_channel_received, @player,
	@uuid = _get_puuid(@player)
	@playerInfo = _cc_get_player_info(@uuid)
	return(@playerInfo['lastReceived'])
)

/**
 * Sets the last channel the player received a message from
 */
proc(_cc_set_last_channel_received, @player, @channel,
	@channel = to_lower(@channel)
	@uuid = _get_puuid(player())
	@playerInfo = _cc_get_player_info(@uuid)
	@playerInfo['lastReceived'] = @channel
	_cc_save_player_info(@uuid, @playerInfo)
)

/**
 * Sends a formatted message to the specified channel, only if the user
 * is in the channel.
 */
proc(_cc_send_message, @channel, @message, @change,
	@channel = to_lower(@channel)
	@channelInfo = _cc_get_channel_info(@channel)
	@uuid = _get_puuid(player())
	if(!array_contains_ic(@channelInfo['members'], @uuid) && player() != '~console'){
		die(color(RED).'You can\'t send a message to a channel you aren\'t a member of')
	}
	console('ClanChat: '.color(WHITE).'['.color(@channelInfo['color']).@channel.color(WHITE).']'.color(RESET).'<'.if(player() == '~console',color(RED).'CONSOLE'.color(RESET),strip_colors(player())).'> '.@message, false)
	if(@change) {
		_cc_set_default(@channel)
	}
	# Permission check succeeded, so send message using raw message
	_cc_send_raw_message(@channel, color(@channelInfo['color']).'['.@channel.']'.color(GRAY).' <'.color(WHITE).if(player() == '~console',color(RED).'CONSOLE'.color(RESET),strip_colors(player())).color(GRAY).'> '.color(@channelInfo['textcolor']).@message)
	foreach(@channelInfo['members'], @member,
		_cc_set_last_channel_received(@member, @channel)
	)
)

/**
 * Sends an underlined alert to the specified channel, only if the user is a manager of that channel.
 */
proc(_cc_send_alert, @channel, @message,
	@channel = to_lower(@channel)
	@channelInfo = _cc_get_channel_info(@channel)
	_cc_assert_manager(@channelInfo)
	console('ClanChat: '.color(WHITE).'['.color(@channelInfo['color']).@channel.color(WHITE).']'.color(RESET).'<'.if(player() == '~console',color(RED).'CONSOLE'.color(RESET),strip_colors(player())).'> '.@message, false)
	_cc_set_default(@channel)
	_cc_send_raw_message(@channel, color(@channelInfo['color']).'['.@channel.']'.color(@channelInfo['alertcolor']).' <'.if(player() == '~console',color(RED).'CONSOLE',player()).'> '.color(UNDERLINE).@message)
	foreach(@channelInfo['members'], @member,
		_cc_set_last_channel_received(@member, @channel)
	)
)

/**
 * Sends a '/me' type message to the specified channel, only if the user is in the channel.
 */
proc(_cc_send_me_message, @channel, @message,
	@channel = to_lower(@channel)
	@channelInfo = _cc_get_channel_info(@channel)
	@uuid = _get_puuid(player())
	if(!array_contains_ic(@channelInfo['members'], @uuid) && player() != '~console'){
		die(color(RED).'You can\'t send a message to a channel you aren\'t a member of')
	}
	console('ClanChat: '.color(WHITE).'['.color(@channelInfo['color']).@channel.color(WHITE).']'.color(RESET).' '.if(player() == '~console',color(RED).'* CONSOLE'.color(RESET),'* '.strip_colors(player())).' '.@message, false)
	_cc_set_default(@channel)
	# Permission check succeeded, so send message using raw message
	_cc_send_raw_message(@channel, color(@channelInfo['color']).'['.@channel.'] '.color(@channelInfo['textcolor']).if(player() == '~console','* CONSOLE','* '.strip_colors(player())).' '.@message)
	foreach(@channelInfo['members'], @member,
		_cc_set_last_channel_received(@member, @channel)
	)
)

/**
 * Sends an unformatted message to the specified channel. There are no
 * permission checks, this is meant for internal use only.
 */
proc(_cc_send_raw_message, @channel, @message,
	@channel = to_lower(@channel)
	@channelInfo = _cc_get_channel_info(@channel)
	@members = @channelInfo['members']
	foreach(@members, @member,
		@memberName = _get_username_from_uuid(@member)
		if(ponline(@memberName)){
			tmsg(@memberName, @message)
		} else if(ponline(color(a).@memberName.color(f))){
			tmsg(color(a).@memberName.color(f), @message)
		}
	)
)

/**
 * Prints a list of all the channels you are subscribed to
 */
proc(_cc_print_channels,
	@uuid = _get_puuid(player())
	@playerInfo = _cc_get_player_info(@uuid)
	@output = array()
	foreachelse(@playerInfo['channels'], @channel,
		@channelInfo = _cc_get_channel_info(@channel)
		array_push(@output, color(@channelInfo['color']).@channel)
	, #else
		msg(color(RED).'You aren\'t in any channels')
	)
	if(array_size(@output) > 0){
		msg(array_implode(@output, color(WHITE).', '))
	}
)

/**
 * Prints all channels and their owners
 */
proc(_cc_print_all_channels,
	@channels = _cc_get_value('clanchat.channels', array())
	@output = array()
	foreach(@channels, @channel,
		@info = _cc_get_channel_info(@channel)
		@owner = @info['owner']
		@ownerName = _get_username_from_uuid(@owner)
		array_push(@output, color(BLUE).@channel.color(WHITE).': '.color(GRAY).@ownerName)
	)
	msg(array_implode(@output, color(WHITE).', '))
)

/**
 * Prints all public channels
 */
proc(_cc_print_all_public_channels,
	@channels = _cc_get_value('clanchat.channels', array())
	@output = array()
	foreach(@channels, @channel,
		@info = _cc_get_channel_info(@channel)
		@public = @info['flags']['public']
		if (@public == true) {
			array_push(@output, color(@info['color']).@channel)
		}
	)
	msg(array_implode(@output, color(WHITE).', '))
)

/**
 * Flag management
 */
proc(_cc_flags, @channel, @flag, @bool,
	@channelInfo = _cc_get_channel_info(@channel)
	@uuid = _get_puuid(player())
	if (@uuid != @channelInfo['owner']) {
		die(color(RED).'This command is only available to the channel owner')
	}
	if (!(or(@flag == 'public', @flag == 'secret'))) {
		die(color(RED).'Invalid command, type /clanchat flags for help (invalid flag)')
	}
	if (!(or(@bool == 'true', @bool == 'false'))) {
		die(color(RED).'Invalid command, type /clanchat flags for help (invalid boolean)'.@bool)
	}
	#at this point, we have an owner, and a valid command. MAGIC TIME.
	@channelInfo['flags'][@flag] = @bool
	_cc_save_channel_info(@channel, @channelInfo)
	msg(color(BLUE).'Clanchat: '.@flag.' has been set to '.@bool.' for '.@channel)
	
)

/**
 * Bulletin methods
 */
proc(_cc_print_bulletins, @channel,
	@channelInfo = _cc_get_channel_info(@channel)
	@uuid = _get_puuid(player())
	if(!array_contains(@channelInfo['members'], @uuid)) {
		die(color(RED).'You must be a member of '.@channel.' to see their bulletins')
	}
	
	if(array_size(@channelInfo['bulletins']) > 0) {
		foreach(@bulletin in @channelInfo['bulletins']) {
			msg(color(@channelInfo['color']).'['.@channel.']'.' '.color(@channelInfo['alertcolor']).@bulletin)
		}
	} else {
		die(color(BLUE).'There are no active bulletins for '.@channel)
	}
)

proc(_cc_print_all_bulletins,
	@uuid = _get_puuid(player())
	@playerInfo = _cc_get_player_info(@uuid)
	foreach(@channel in @playerInfo['channels']) {
		if(array_size(_cc_get_channel_info(@channel)['bulletins']) > 0) {
			_cc_print_bulletins(@channel)
		}
	}
)

proc(_cc_add_bulletin, @channel, @bulletin,
	@channelInfo = _cc_get_channel_info(@channel)
	_cc_assert_manager(@channelInfo)
	array_push(@channelInfo['bulletins'], @bulletin)
	_cc_save_channel_info(@channel, @channelInfo)
	msg(color(BLUE).'Bulletin added successfully.')
	_cc_send_raw_message(@channel, color(@channelInfo['color']).'['.@channel.']'.' '.color(@channelInfo['alertcolor']).@bulletin)
)

proc(_cc_remove_bulletin, @channel, @index,
	@channelInfo = _cc_get_channel_info(@channel)
	_cc_assert_manager(@channelInfo)
	if(!is_integral(@index) || @index < 1) {
		die(color(RED).'The bulletin index specified must be a non-zero integer')
	}
	if(array_index_exists(@channelInfo['bulletins'], @index - 1)) {
		array_remove(@channelInfo['bulletins'], @index - 1)
		_cc_save_channel_info(@channel, @channelInfo)
		msg(color(BLUE).'Bulletin successfully removed')
	} else {
		die(color(RED).'There is no bulletin at that index')
	}
)

proc(_cc_subscribe_bulletins, @channel,
	@uuid = _get_puuid(player())
	@playerInfo = _cc_get_player_info(@uuid)
	@channelInfo = _cc_get_channel_info(@channel)
	if(!array_contains(@channelInfo['members'], @uuid)) {
		die(color(RED).'You must be a member of '.@channel.' to subscribe to their bulletins')
	}
	if(array_contains_ic(@playerInfo['subscribed'], @channel)) {
		die(color(RED).'You are already subscribed to that channel')
	} else {
		array_push(@playerInfo['subscribed'], @channel)
		_cc_save_player_info(@uuid, @playerInfo)
		msg(color(BLUE).'You are now subscribed to bulletins made in '.@channel)
	}
)

proc(_cc_unsubscribe_bulletins, @channel,
	@uuid = _get_puuid(player())
	@playerInfo = _cc_get_player_info(@uuid)
	if(array_contains_ic(@playerInfo['subscribed'], @channel)) {
		array_remove_values(@playerInfo['subscribed'], @channel)
		_cc_save_player_info(@uuid, @playerInfo)
		msg(color(BLUE).'You are now unsubscribed from bulletins made in '.@channel)
	} else {
		die(color(RED).'You are not subscribed to that channel.')
	}
)

proc(_cc_print_bulletin_subscriptions,
	@uuid = _get_puuid(player())
	@playerInfo = _cc_get_player_info(@uuid)
	@subscribed = array_implode(@playerInfo['subscribed'],', ')
	if(length(@subscribed) > 0) {
		msg(color(BLUE).'Current subscriptions: '.color(GRAY).@subscribed)
	} else {
		die(color(BLUE).'You have no current subscriptions.')
	}
)

/*
 * Utility methods
 */

/**
 * Gets a value from the database, if it's set. If not, it returns the default value,
 * which defaults to null.
 */
proc(_cc_get_value, @key, @default = null,
	if(has_value(@key)){
		return(get_value(@key))
	} else {
		return(@default)
	}
)

proc(_cc_format_list, @array, @color1 = WHITE, @color2 = GRAY,
	@first = true
	@string = ''
	@index = 0
	foreach(@array, @value,
		if(!@first){
			@string .= color(WHITE).', '
		}
		@first = false
		(@index++)
		@color = color(if(@index % 2 == 0, @color1, @color2))
		@string .= @color.@value
	)
	return(@string)
)

proc(_cc_get_channel_info, @channel,
	@channel = to_lower(@channel)
	@channelInfo = _cc_get_value('clanchat.channels.'.@channel, null)
	if(@channelInfo == null){
		die(color(RED).'The channel "'.@channel.'" doesn\'t exist')
	} else {
		@keys = array_keys(@channelInfo);
		if(!array_contains(@keys, 'flags')) {
			@channelInfo['flags'] = array(
				public: false,
				secret: false
			)
		}
		if(!array_contains(@keys, 'bulletins')) {
			@channelInfo['bulletins'] = array()
		}
		if(!array_contains(@keys, 'textcolor')) {
			@channelInfo['textcolor'] = GRAY
		}
		if(!array_contains(@keys, 'alertcolor')) {
			@channelInfo['alertcolor'] = GRAY
		}
		return(@channelInfo)
	}
)

proc(_cc_get_player_info, @uuid,
	@playerInfo = (_cc_get_value('clanchat.players.'.@uuid, array(
		default: null, 
		channels: array(),
		lastReceived: null,
		subscribed: array()
	)))
	
	if(!array_contains(array_keys(@playerInfo), 'subscribed')) {
		@playerInfo['subscribed'] = array()
	}
	
	return(@playerInfo)
)

proc(_cc_save_player_info, @uuid, @playerInfo,
	if(@uuid == '~console'){
		return()
	}
	store_value('clanchat.players.'.@uuid, @playerInfo)
)

proc(_cc_save_channel_info, @channel, @channelInfo,
	@channel = to_lower(@channel)
	store_value('clanchat.channels.'.@channel, @channelInfo)
)

proc(_cc_assert_manager, @channelInfo,
	@uuid = _get_puuid(player())
	if ((@channelInfo['owner'] != @uuid) && !array_contains_ic(@channelInfo['managers'], @uuid)) {
		die(color(RED).'Sorry, you have to be a manager to do that!')
	}
)
