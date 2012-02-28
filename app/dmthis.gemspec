Gem::Specification.new do |s|
  s.name = 'dmthis'
  s.summary = 'Daemon for monitoring Tweets and sending them to interested ' +
              'parties via DM'
  s.description  = File.read(File.join(File.dirname(__FILE__), 'README'))
  s.requirements = ['Twitter application key and secret']
  s.version = '0.0.1'
  s.author = 'Chris Bennett'
  s.email = 'chris@mruser.com'
  s.homepage = 'http://mruser.com/'
  s.platform    = Gem::Platform::RUBY
  s.required_ruby_version = '>=1.9.3'
  s.date = '2012-02-24'
  s.files = [
    "Gemfile",
    "Rakefile",
    "lib/**",
    "bin/**"
  ]
  s.has_rdoc = false
  s.license = 'MIT'
end
