#!/usr/bin/env ruby
# encoding: UTF-8
require 'rubygems'
require 'bundler/setup'
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
    logger.info("DM from #{sender.screen_name}: #{dm.text}")
    logger.debug(dm)
    # who might they want to follow/unfollow
    dm.text.scan(/\@(\p{L}+)/) do |group|
      # lookup ID for sn
      sn = group[0]
      id = Twitter.user(sn).id
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
  # TODO: daemonize
  #puts "Listening..."
  #dmclient.userstream
  #exit

  lclient = TweetStream::Client.new
  lclient.on_error do |err|
    logger.error(err)
  end
  user_ids_to_follow = DMFollow.select('DISTINCT rgt_id').collect { |inst| inst.rgt_id }
  lclient.follow(user_ids_to_follow) do |status|
    # lookup who is interested in this status and DM them
    DMFollow.where(rgt_id: status.user.id).each do |dmf|
      # TODO: Trunc needs to be a heuristic
      Twitter.direct_message_create(dmf.lft_id, "@#{status.user.screen_name} #{status.text}"[0..139])
    end
  end

  
end
