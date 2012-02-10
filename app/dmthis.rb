#!/usr/bin/env ruby
# encoding: UTF-8
require 'active_record'
require 'tweetstream'
require 'twitter'
require 'log4r'
include Log4r

logger = Logger.new 'main'
logger.outputters = Outputter.stdout

$config = YAML::load(File.open(File.join(File.dirname(__FILE__), 'config.yml')))[ENV['ENV'] || 'development']
$db_config = YAML::load(File.open(File.join(File.dirname(__FILE__), 'db', 'config.yml')))[ENV['ENV'] || 'development']

def configure_twitter
  conf_proc = Proc.new { |conf|
    twitter_conf = $config['twitter']
    conf.consumer_key = twitter_conf['consumer_key']
    conf.consumer_secret = twitter_conf['consumer_secret']
    conf.oauth_token = twitter_conf['main_oauth_token']
    conf.oauth_token_secret = twitter_conf['main_oauth_token_secret']
  }
  Twitter.configure &conf_proc
  TweetStream.configure do |conf|
    conf_proc.call(conf)
    conf.auth_method = :oauth
    conf.parser = :yajl
  end
end

def format_message_from_status(status)
  # make sure we don't trunc the sender 
  # or urls (any token with a / will suffice for now)
  from_text = "@#{status.user.screen_name} "
  text = shorten_but_urls(status.text, 140 - from_text.length)

  return "#{from_text}#{text}"
end

def shorten_but_urls(text, length_available)
  if text.length > length_available
    tokenized_text = text.split
    shortenable_tokens = tokenized_text.collect do |val|
      next val unless val.include? '/'
    end
    ellip = '...'
    to_shorten = text.length + ellip.length - length_available
    shortened = false
    shortenable_tokens.reverse!.collect! do |val|
      next if val == nil
      if to_shorten > 0
        val_length = val.length
        shorten_by = [val_length, to_shorten].min
        val = val.slice(0, val_length-shorten_by)
        to_shorten -= shorten_by + 1
        if !shortened && val_length != shorten_by 
          shortened = true
          next "#{val}#{ellip}"
        else
          next val
        end
      end
    end
    shortenable_tokens.reverse!

    return tokenized_text.collect.with_index { |val, i|
      val = shortenable_tokens[i] if shortenable_tokens[i] != nil
      if !shortened && shortenable_tokens.length-1 > i && shortenable_tokens[i+1].empty?
        shortened = true
        val << ellip
      end
      val
    }.reject {|val| val.empty? }.join(' ').sub(" #{ellip}", ellip).strip
  else
    text.strip
  end
end

if __FILE__ == $PROGRAM_NAME
  ActiveRecord::Base.establish_connection($db_config)
  configure_twitter
 
  require './models'
  DMFollow.all.each do |inst|
    puts inst.rgt
  end
  dmclient = TweetStream::Client.new
  dmclient.on_direct_message do |dm|
    sender = dm.sender
    next if sender.id == $config['twitter']['account_id']
    logger.info("DM from #{sender.screen_name}: #{dm.text}")
    logger.debug(dm)
    # who might they want to follow/unfollow
    dm.text.scan(/\@([\p{L}0-9_]{3,15})/) do |group|
      # lookup ID for sn
      sn = group[0]
      begin
        id = Twitter.user(sn).id
      rescue
        logger.error("Unable to lookup user: #{sn}, #{$!}")
      end
      # add or remove from table
      inst = DMFollow.where(lft: sender.screen_name,
                            lft_id: sender.id,
                            rgt: sn,
                            rgt_id: id).first_or_initialize
      if inst.new_record?
        logger.debug("Creating DMFollow: lft: #{sender.screen_name}," +
                     "lft_id: #{sender.id}, rgt: #{sn}," +
                     "rgt_id: #{id}")
        inst.save
      else
        # remove it
        inst.delete
        logger.debug("Removed DMFollow: lft: #{sender.screen_name}," +
                     "lft_id: #{sender.id}, rgt: #{sn}," +
                     "rgt_id: #{id}")
      end
    end
  end

  dmclient.on_error do |err|
    puts err
    logger.error(err.inspect)
  end

  trap("CLD") {
    pid = Process.wait
    puts "Child pid #{pid}: terminated"
    exit 1
  }

  Kernel::fork do
    running = true
    while running
      begin
        dmclient.userstream
      rescue HTTP::Parser::Error
        logger.error("HTTP::Parser::Error #{$!}")
        next
      rescue
        running = false
        raise
      end
    end
  end

  lclient = TweetStream::Client.new
  lclient.on_error do |err|
    logger.error(err)
  end
  # TODO: This will need to reload periodically or after dmfollow is updated
  user_ids_to_follow = DMFollow.select('DISTINCT rgt_id').collect { |inst| inst.rgt_id }
   
  running = true
  while running
    begin
      lclient.follow(user_ids_to_follow) do |status|
        # lookup who is interested in this status and DM them
        DMFollow.where(rgt_id: status.user.id).each do |dmf|
          message = format_message_from_status status
          Twitter.direct_message_create(dmf.lft_id, message)
        end
      end
    rescue HTTP::Parser::Error
      logger.error("HTTP::Parser::Error #{$!}")
      next
    rescue
      running = false
      raise
    end
  end
  
end
