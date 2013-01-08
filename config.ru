require './boot'

use Rack::Session::Cookie, :secret => ENV['SESSION_SECRET'] || 'changemeplease'
use Rack::Flash, :accessorize => [:info, :error]

if ENV['RACK_ENV'] || 'development' == 'development'
  require 'new_relic/rack/developer_mode'
  use NewRelic::Rack::DeveloperMode
end

set :partial_template_engine, :erb
enable :partial_underscores

helpers do
  alias_method :h, :escape_html
end

run Sinatra::Application
