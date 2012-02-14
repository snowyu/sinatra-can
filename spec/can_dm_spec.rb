require 'rspec'
require 'rack/test'
require 'sinatra'
require 'dm-core'
require 'dm-migrations'
require './lib/sinatra/can'

describe 'sinatra-can' do
  include Rack::Test::Methods

  class MyAppDM < Sinatra::Application
  end

  def app
    MyAppDM
  end

  before :all do
    DataMapper.setup(:default, 'sqlite::memory:')

    class Article
      include DataMapper::Resource

      property :id, Serial
      property :title, String
    end

    class User
      include DataMapper::Resource

      property :id, Serial
      property :name, String

      def is_admin?
        @name == "admin"
      end
    end

    DataMapper.finalize
    DataMapper.auto_upgrade!

    ability do |user|
      can :edit, :all if user.is_admin?
      can :read, :all
      can :read, Article
      cannot :create, Article
      can :list, User if user.is_admin?
      can :list, User, :id => user.id
    end

    app.set :dump_errors, true
    app.set :raise_errors, true
    app.set :show_exceptions, false

    User.create(:name => 'admin')
    User.create(:name => 'guest')
  end

  it "should allow management to the admin user" do
    app.user { User.get(1) }
    app.get('/1') { can?(:edit, :all).to_s }
    get '/1'
    last_response.body.should == 'true'
  end

  it "shouldn't allow management to the guest" do
    app.user { User.get(2) }
    app.get('/2') { cannot?(:edit, :all).to_s }
    get '/2'
    last_response.body.should == 'true'
  end

  it "should act naturally when authorized" do
    app.user { User.get(1) }
    app.get('/3') { authorize!(:edit, :all); 'okay' }
    get '/3'
    last_response.body.should == 'okay'
  end

  it "should raise errors when not authorized" do
    app.user { User.get(2) }
    app.get('/4') { authorize!(:edit, :all); 'okay' }
    get '/4'
    last_response.status.should == 403
  end

  it "should respect the 'user' block" do
    app.user { User.create(:name => 'testing') }
    app.get('/5') { current_user.name }
    get '/5'
    last_response.body.should == "testing"
  end

  it "shouldn't allow a rule if it's not declared" do
    app.user { User.get(1) }
    app.get('/6') { can?(:destroy, :all).to_s }
    get '/6'
    last_response.body.should == "false"
  end

  it "should throw 403 errors upon failed conditions" do
    app.user { User.get(1) }
    app.get('/7', :can => [ :create, User ]) { 'ok' }
    get '/7'
    last_response.status.should == 403
  end

  it "should accept conditions" do
    app.user { User.get(1) }
    app.get('/8', :can => [ :edit, :all ]) { 'ok' }
    get '/8'
    last_response.status.should == 200
  end

  it "should accept not_auth and redirect when not authorized" do
    app.user { User.get(2) }
    app.get('/login') { 'login here' }
    app.get('/9') { authorize! :manage, :all, :not_auth => '/login'  }
    get '/9'
    follow_redirect!
    last_response.body.should == 'login here'
  end

  it "should autoload and autorize the model" do
    article = Article.create(:title => 'test1')

    app.user { User.get(1) }
    app.get('/10/:id') { load_and_authorize!(Article); @article.title }
    get '/10/' + article.id.to_s
    last_response.body.should == article.title
  end

  it "should shouldn't allow creation of the model" do
    article = Article.create(:title => 'test2')

    app.user { User.get(1) }
    app.post('/11', :model => Proc.new { Article }) { }
    post '/11'
    last_response.status.should == 403
  end

  it "should autoload and autorize the model when using the condition" do
    article = Article.create(:title => 'test3')

    app.user { User.get(1) }
    app.get('/12/:id', :model => Proc.new { Article }) { @article.title }
    get '/12/' + article.id.to_s
    last_response.body.should == article.title
  end

  it "should autoload when using the before do...end block" do
    article = Article.create(:title => 'test4')

    app.user { User.get(1) }
    app.before('/13/:id', :model => Proc.new { Article }) { }
    app.get('/13/:id') { @article.title }
    get '/13/' + (article.id).to_s
    last_response.body.should == article.title
  end

  it "should return a 404 when the autoload fails" do
    dummy = Article.create(:title => 'test4')

    app.user { User.get(1) }
    app.get('/article14/:id', :model => Proc.new { Article }) { @article.title }
    get '/article14/999'
    last_response.status.should == 404
  end

  it "should autoload a collection as the admin" do
    app.user { User.get(1) }
    app.get('/15', :model => Proc.new { User }) { @user.all(:name => 'admin').count.to_s }
    get '/15'
    last_response.body.should == '1'
  end

  it "should 403 on autoloading a collection when being a guest" do
    app.user { User.get(2) }
    app.get('/16', :model => Proc.new { User }) { @user.all(:name => 'admin').count.to_s }
    get '/16'
    last_response.body.should == "0"
  end
end
