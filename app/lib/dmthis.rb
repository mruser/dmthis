# encoding: UTF-8
require 'log4r'

logger = Log4r::Logger.new 'main'
logger.outputters << Log4r::Outputter.stdout
logger.outputters << Log4r::FileOutputter.new('dmthis_log', filename: 'dmthis.log')

require 'dmthis/models'
require 'dmthis/daemon'
