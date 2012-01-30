#!/usr/bin/env ruby
# encoding: UTF-8
require "rubygems"
require "bundler/setup"
require "active_record"

if __FILE__ == $PROGRAM_NAME
  db_config = YAML::load(File.open(File.join(File.dirname(__FILE__), "config", "database.yml")))[ENV["ENV"] ? ENV["ENV"] : "dev"]
  ActiveRecord::Base.establish_connection(db_config)

  Dir.glob("./models/*").each { |r| require r }
  puts "Done"
end
