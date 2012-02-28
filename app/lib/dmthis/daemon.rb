# encoding: UTF-8

require 'active_record'
require 'tweetstream'
require 'twitter'
require 'log4r'
require 'dmthis/configuration'
require 'dmthis/utils'

$logger = Log4r::Logger['main']


# update_user_ids after an interval (easy) or after updates (TODO)
UPDATE_USER_IDS_INTERVAL = 22
def update_user_ids
  $user_ids_to_follow = DMFollow.select('DISTINCT rgt_id')
                                .collect { |inst| inst.rgt_id }
end

def process_follow_status(status)
  # lookup who is interested in this status and DM them
  DMFollow.where(rgt_id: status.user.id).each do |dmf|
    message = format_message_from_status(status)
    Twitter.direct_message_create(dmf.lft_id, message)
  end
end

def process_incoming_dm(message)
  $logger.debug(message)
  text = message.text
  if message[:sender]
    sender = message.sender
    $logger.info("DM from #{sender.screen_name}: #{message.text}")
  else
    sender = message.user
    $logger.info("status from #{sender.screen_name}: #{message.text}")
    # remove @account before processing; also return if not contained
    return unless text.gsub!(/\@#{$config['twitter']['screen_name']} /i, '')
  end
  return if sender.id == $config['twitter']['account_id']

  # check to make sure we're being followed
  # friendships/lookup
  begin
    rel = Twitter.friendship($config['twitter']['account_id'], sender.id)
    $logger.debug(rel)
    if !rel.target.following
      $logger.info("not followed by #{sender.screen_name}")
      return
    end
  rescue
    $logger.error("Unable to lookup relationship: #{$!}")
  end

  # check for action words
  action = nil
  if text.match($start_words_re)
    action = :start
  elsif text.match($stop_words_re)
    action = :stop
  end

  return if not action

  # who might they want to follow/unfollow
  text.scan(/\@([\p{L}0-9_]{2,15})/) do |group|
    # lookup ID for sn
    sn = group[0]
    begin
      id = Twitter.user(sn).id
    rescue
      $logger.error("Unable to lookup user: #{sn}, #{$!}")
      return
    end
    # add or remove from table
    inst = DMFollow.where(lft: sender.screen_name,
                          lft_id: sender.id,
                          rgt: sn,
                          rgt_id: id).first_or_initialize
    if action == :start && inst.new_record?
      # Get current list of followers
      current_followers = DMFollow.where(lft_id: sender.id)
      if current_followers.length == MAX_FOLLOWERS
        # reply not possible via DM
        Twitter.direct_message_create(sender.id,
                                      "Unable to add #{sn}, a " +
                                      "max of #{MAX_FOLLOWERS} are allowed")
        return
      end
      $logger.debug("Creating DMFollow: lft: #{sender.screen_name}," +
                   "lft_id: #{sender.id}, rgt: #{sn}," +
                   "rgt_id: #{id}")
      inst.save
    elsif inst && action == :stop
      # remove it
      inst.delete
      $logger.debug("Removed DMFollow: lft: #{sender.screen_name}," +
                   "lft_id: #{sender.id}, rgt: #{sn}," +
                   "rgt_id: #{id}")
    else
      # noop
      return
    end

    # send a status message
    follow_sns = DMFollow.where(lft_id: sender.id)
                         .collect { |inst| inst.rgt }
    if follow_sns.length
      message = "Now following: #{follow_sns.join(',')}"
    else
      message = "Not following anyone"
    end
    Twitter.direct_message_create(sender.id, message)
  end
end


def start_dmthis
  ActiveRecord::Base.establish_connection($db_config)
  configure_twitter

  dmclient = TweetStream::Client.new
  on_action = Proc.new do |message|
    process_incoming_dm(message)
  end
  dmclient.on_timeline_status &on_action
  dmclient.on_direct_message &on_action

  dmclient.on_error do |err|
    $logger.error(err.inspect)
  end

  # parent traps
  trap('CLD') do
    pid = Process.wait
    $logger.error("Child pid #{pid}: terminated")
    exit 1
  end

  Kernel::fork do
    running = true
    while running
      begin
        dmclient.start('', extra_stream_parameters:
                       {host: 'userstream.twitter.com',
                        path: '/2/user.json',
                        replies: 'all'
                       }
                      )
      rescue HTTP::Parser::Error
        $logger.error("HTTP::Parser::Error #{$!}")
        # needs backoff method
        dmclient.stop_stream
        next
      rescue
        running = false
        raise
      end
    end
  end

  lclient = TweetStream::Client.new
  lclient.on_error do |err|
    $logger.error(err)
  end

  lclient.on_interval(UPDATE_USER_IDS_INTERVAL) do
    lclient.stop
  end

  running = true
  while running
    update_user_ids
    begin
      lclient.follow($user_ids_to_follow) do |status|
        process_follow_status(status)
      end
    rescue HTTP::Parser::Error
      $logger.error("HTTP::Parser::Error #{$!}")
      next
    rescue
      running = false
      $logger.error("Unhandled exception")
      raise
    end
  end
end
