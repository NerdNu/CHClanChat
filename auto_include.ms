
/*
 * DB Schema:
 * clanchat.channels - An array of all the channels
 * clanchat.channels.<channel> - An array of all the channel infos:
 * 				- managers: array of managers
 *				- invites: array of invited, but not yet accepted players
 *				- members: array of players in this channel (including managers and the owner)
 *				- owner: The owner's name
 * clanchat.players - An associative array of all the players (key) with their player infos:
 *				- lastReceived: The last channel they receieved a message from
 * 				- default: Their default channel name
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
		@channelInfo = array(
			managers: array(),
			invites: array(),
			members: array(to_lower(player())),
			owner: to_lower(player()),
			color: 'BLUE'
		)
		store_value('clanchat.channels.'.@channel, @channelInfo)
		@playerInfo = _cc_get_player_info(player())
		array_push(@playerInfo['channels'], @channel)
		_cc_save_player_info(player(), @playerInfo)
		_cc_set_default(@channel)
		die(color(LIGHT_PURPLE).'Channel created!')
	}
)

proc(_cc_change_owner, @channel, @newOwner,
	@channel = to_lower(@channel)
	@channelInfo = _cc_get_channel_info(@channel)
	#make sure the player is the current owner
	if ((to_lower(player()) != @channelInfo['owner']) && (player() != '~console')){
		die(color(RED).'Only the owner can set a new owner for the channel')
	}
	# set the new owner, add the old owner to the managers list
	@channelInfo['owner'] = to_lower(@newOwner)
	_cc_save_channel_info(@channel, @channelInfo)
	die(color(AQUA).'You have relinquished ownership on '.@channel.' to '.@newOwner.')
)

proc(_cc_set_channel_color, @channel, @color,
	@colors = array(BLACK, DARK_BLUE, DARK_GREEN, DARK_AQUA, DARK_RED, DARK_PURPLE, GOLD, GRAY, DARK_GRAY, 
		BLUE, GREEN, AQUA, RED, LIGHT_PURPLE, YELLOW, WHITE)
	@channel = to_lower(@channel)
	@channelInfo = _cc_get_channel_info(@channel)
	if(to_lower(player()) != @channelInfo['owner']){
		die(color(RED).'Only the owner can change the channel\'s color.')
	}
	@color = to_upper(@color)
	if(array_contains(@colors, @color)){
		@channelInfo['color'] = @color
		_cc_save_channel_info(@channel, @channelInfo)
		die(color(BLUE).'Channel color changed to '.color(@color).@color.'!')
	} else {
		@output = array()
		foreach(@colors, @color,
			array_push(@output, color(@color).@color)
		)
		die('Only one of the following can be set as the channel color: '.array_implode(@output, color(WHITE).', '))
	}
)

/**
 * Messages out a list of all the players in the given channel
 */
proc(_cc_print_members, @channel,
	@channel = to_lower(@channel)
	@channelInfo = _cc_get_channel_info(@channel)
	@members = @channelInfo['members']
	@online = array()
	@offline = array()
	foreach(@members, @member,
		if(ponline(@member)){
			array_push(@online, player(@member))
		} else {
			array_push(@offline, @member)
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
	@channelInfo = _cc_get_channel_info(@channel)
	_cc_assert_manager(@channelInfo)
	@invites = @channelInfo['invites']
	if(!array_contains(@invites, @player)){
		array_push(@invites, @player)
		_cc_save_channel_info(@channel, @channelInfo)
		if(ponline(@player)){
			# Also inform them if they are online. If not, oh well.
			tmsg(@player, color(BLUE).'You have been invited to "'.@channel.'" by '.player().'.')
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
	@channelInfo = _cc_get_channel_info(@channel)
	_cc_assert_manager(@channelInfo)
	@invites = @channelInfo['invites']
	if(!array_contains(@invites, @player)){
		die(color(RED).'That player isn\'t in the invite list.')
	} else {
		array_remove_values(@invites, @player)
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
	@channelInfo = _cc_get_channel_info(@channel)
	if(@channelInfo['owner'] != to_lower(player())){
		die(color(RED).'Only the owner may add or remove managers')
	}
	@managers = @channelInfo['managers']
	@members = @channelInfo['members']
	if(!array_contains(@members, @player)){
		die(color(RED).'Only members can be made managers. Invite them to the channel, and wait for them to join first.')
	} else if(array_contains(@managers, @player)){
		die(color(RED).@player.' is already a manager')
	} else {
		array_push(@managers, @player)
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
	@channelInfo = _cc_get_channel_info(@channel)
	if(@channelInfo['owner'] != to_lower(player())){
		die(color(RED).'Only the owner may add or remove managers')
	}
	@managers = @channelInfo['managers']
	if(array_contains(@managers, @player)){
		array_remove_values(@managers, @player)
		_cc_save_channel_info(@channel, @channelInfo)
		die(color(BLUE).'Player removed as a manager from '.@channel)
	} else {
		die(color(RED).@player.' is not a manager in '.@channel)
	}
)

/**
 * Removes a player from this channel. The owner cannot be removed, and managers can
 * only be removed by the owner, and normal users don't have access at all.
 */
proc(_cc_remove_member, @channel, @player,
	@channel = to_lower(@channel)
	@player = to_lower(@player)
	@channelInfo = _cc_get_channel_info(@channel)
	_cc_assert_manager(@channelInfo)
	if(@channelInfo['owner'] == @player){
		die(color(RED).'You cannot remove the owner from a channel!')
	}
	if(to_lower(player()) != @channelInfo['owner'] && array_contains(@channelInfo['managers'], @player)){
		die(color(RED).'Only the owner can remove a manager')
	}
	if(!array_contains(@channelInfo['members'], @player)){
		die(color(RED).'That player isn\'t a member.')
	}
	# At this point, they are a manager, and we aren't trying to remove a manager
	array_remove_values(@channelInfo['members'], @player)
	array_remove_values(@channelInfo['managers'], @player)
	@playerInfo = _cc_get_player_info(@player)
	array_remove_values(@playerInfo['channels'], @channel)
	_cc_save_player_info(@player, @playerInfo)
	_cc_save_channel_info(@channel, @channelInfo)
	die(color(BLUE).'Member removed.')
)

/**
 * Joins a channel, if the user has been invited.
 */
proc(_cc_join_channel, @channel,
	@channel = to_lower(@channel)
	@channelInfo = _cc_get_channel_info(@channel)
	if(!array_contains_ic(@channelInfo['invites'], player())){
		die(color(RED).'You can\'t join a channel without an invite, so speak with '.@channelInfo['owner'].' about joining')
	}
	array_remove_values(@channelInfo['invites'], to_lower(player()))
	array_push(@channelInfo['members'], to_lower(player()))
	@playerInfo = _cc_get_player_info(player())
	array_push(@playerInfo['channels'], @channel)
	_cc_save_player_info(player(), @playerInfo)
	_cc_set_default(@channel)
	_cc_save_channel_info(@channel, @channelInfo)
	msg(color(BLUE).'Type '.color(GRAY).'/c #'.@channel.' <msg>'.color(BLUE).' to say something to this channel, or just '.color(GRAY).'/c <msg>'.color(BLUE)
		.' if this is already your default channel')
	_cc_send_raw_message(@channel, color(RED).player().color(BLUE).' has joined '.color(@channelInfo['color']).@channel.color(BLUE).', say hi!')
)

/**
 * Allows a user to leave the channel themselves, but otherwise works like
 * _cc_remove_member(@channel, player())
 */
proc(_cc_leave_channel, @channel,
	@channel = to_lower(@channel)
	@channelInfo = _cc_get_channel_info(@channel)
	if(!array_contains(@channelInfo['members'], to_lower(player()))){
		die(color(RED).'You can\'t leave a channel you\'re not in')
	}
	array_remove_values(@channelInfo['members'], to_lower(player()))
	@playerInfo = _cc_get_player_info(player())
	array_remove_values(@playerInfo['channels'], @channel)
	_cc_save_player_info(player(), @playerInfo)
	_cc_save_channel_info(@channel, @channelInfo)
	die(color(BLUE).'You have been removed from '.@channel)
)

/**
 * Sets the player's default channel. If this is different than the previous channel,
 * then they are sent a message telling them their default channel has changed.
 */
proc(_cc_set_default, @channel,
	if(player() == '~console'){
		return()
	}
	@channel = to_lower(@channel)
	@playerInfo = _cc_get_player_info(player())
	if(@playerInfo['default'] != @channel){
		@playerInfo['default'] = @channel
		_cc_save_player_info(player(), @playerInfo)
		msg(color(DARK_BLUE).'Your default channel has been changed to '.@channel)
	}
)

/**
 * Returns the player's default channel
 */
proc(_cc_get_default,
	@playerInfo = _cc_get_player_info(player())
	return(@playerInfo['default'])
)

/**
 * Returns the last channel the player sent a message to
 */
proc(_cc_get_last_channel_received, @player,
	@playerInfo = _cc_get_player_info(@player)
	return(@playerInfo['lastReceived'])
)

/**
 * Sets the last channel the player recieved a message from
 */
proc(_cc_set_last_channel_received, @player, @channel,
	@channel = to_lower(@channel)
	@playerInfo = _cc_get_player_info(@player)
	@playerInfo['lastReceived'] = @channel
	_cc_save_player_info(@player, @playerInfo)
)

/**
 * Sends a formatted message to the specified channel, only if the user
 * is in the channel.
 */
proc(_cc_send_message, @channel, @message,
	@channel = to_lower(@channel)
	@channelInfo = _cc_get_channel_info(@channel)
	if(!array_contains_ic(@channelInfo['members'], player()) && player() != '~console'){
		die(color(RED).'You can\'t send a message to a channel you aren\'t a member of')
	}
	console('ClanChat: '.color(WHITE).'['.color(@channelInfo['color']).@channel.color(WHITE).']'.color(RESET).'<'.if(player() == '~console',color(RED).'CONSOLE'.color(RESET),player()).'> '.@message, false)
	_cc_set_default(@channel)
	# Permission check succeeded, so send message using raw message
	_cc_send_raw_message(@channel, color(@channelInfo['color']).'['.@channel.']'.color(GRAY).' <'.color(WHITE).if(player() == '~console',color(RED).'CONSOLE'.color(RESET),player()).color(GRAY).'> '.color(GRAY).@message)
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
	foreach(@channelInfo['members'], @member,
		if(ponline(@member)){
			tmsg(@member, @message)
		}
	)
)

/**
 * Prints a list of all the channels you are subscribed to
 */
proc(_cc_print_channels,
	@playerInfo = _cc_get_player_info(player())
	@output = array()
	foreach(@playerInfo['channels'], @channel,
		@channelInfo = _cc_get_channel_info(@channel)
		array_push(@output, color(@channelInfo['color']).@channel)
	)
	msg(array_implode(@output, color(WHITE).', '))
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
		array_push(@output, color(BLUE).@channel.color(WHITE).': '.color(GRAY).@owner)
	)
	msg(array_implode(@output, color(WHITE).', '))
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
		return(@channelInfo)
	}
)

proc(_cc_get_player_info, @player,
	@player = to_lower(@player)
	return(_cc_get_value('clanchat.players.'.@player, array(
		default: null, 
		channels: array(),
		lastReceived: null
	)))
)

proc(_cc_save_player_info, @player, @playerInfo,
	if(@player == '~console'){
		return()
	}
	@player = to_lower(@player)
	store_value('clanchat.players.'.@player, @playerInfo)
)

proc(_cc_save_channel_info, @channel, @channelInfo,
	@channel = to_lower(@channel)
	store_value('clanchat.channels.'.@channel, @channelInfo)
)

proc(_cc_assert_manager, @channelInfo,
	if(@channelInfo['owner'] != to_lower(player()) && !array_contains_ic(@channelInfo['managers'], player())){
                die(color(RED).'Sorry, you have to be a manager to do that!')
        }
)
