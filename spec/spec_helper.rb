#CANCAN_TWO = true

if Object.const_defined? :CANCAN_TWO
  gem 'cancan', '=2.0.0.alpha'
else
  gem 'cancan', '=1.6.7'
end

require 'rspec'
require 'rack/test'
require 'sinatra'
require 'dm-core'
require 'dm-migrations'
require 'active_record'
require 'cancan'
require './lib/sinatra/can'

ActiveRecord::Base.establish_connection(:adapter => 'sqlite3', :database => ':memory:')
