# encoding: UTF-8

require 'tweetstream'
require 'twitter'

def load_config(filename)
  path = File.join(File.dirname(__FILE__), "../../config/#{filename}")
  conf = YAML::load(File.open(path))
  return conf[ENV['ENV'] || 'development']
end

$config = load_config("app.yml")
$db_config = load_config("database.yml")

STOP_WORDS = %w{ stop block no unfollow }.join '|'
START_WORDS = %w{ start go follow begin }.join '|'
MAX_FOLLOWERS = $config['max_followers']

$start_words_re = Regexp.new /\b(#{START_WORDS})\b/
$stop_words_re = Regexp.new /\b(#{STOP_WORDS})\b/

def configure_twitter
  conf_proc = Proc.new { |conf|
    twitter_conf = $config['twitter']
    conf.consumer_key = twitter_conf['consumer_key']
    conf.consumer_secret = twitter_conf['consumer_secret']
    conf.oauth_token = twitter_conf['main_oauth_token']
    conf.oauth_token_secret = twitter_conf['main_oauth_token_secret']
  }
  Twitter.configure(&conf_proc)
  TweetStream.configure do |conf|
    conf_proc.call(conf)
    conf.auth_method = :oauth
    conf.parser = :yajl
  end
end
