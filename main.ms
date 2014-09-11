/**
 * Player login event to display bulletins from subscribed channels.
 */
bind(player_login, null, null, @event,
	@player = strip_colors(@event['player'])
	@playerInfo = _cc_get_player_info(@player)
	set_timeout(500, closure(){
		foreach(@subscription in @playerInfo['subscribed']) {
			@channelInfo = _cc_get_channel_info(@subscription)
						tmsg(@player, color(BLUE).'Bulletins for '.color(@channelInfo['color']).@subscription.color(BLUE).':')
			foreach(@bulletin in @channelInfo['bulletins']) {
				tmsg(@player, color(@channelInfo['color']).'['.@subscription.']'.' '.color(@channelInfo['alertcolor']).@bulletin)
			}
		}
		tmsg(@player, color(BLUE).'Run /cb [#channel] to see all your channel bulletins!')
	})
)