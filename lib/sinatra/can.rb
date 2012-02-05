require 'cancan/ability'
require 'cancan/rule'

module Sinatra
  # Sinatra::Can is a lightweight wrapper for CanCan. It contains a partial implementation of the ActiveController helpers.
  module Can
    # Helpers for Sinatra
    module Helpers
      # The can? method receives an action and an object as parameters and checks if the current user is allowed, as declared on the Ability. This method is a helper that can be used inside blocks:
      #
      #   can? :destroy, @project
      #
      # And in views too, of course
      #
      #   <% if can? :create, Project %>
      #     <%= link_to "New Project", new_project_path %>
      #   <% end %>
      def can?(action, subject, options = {})
        current_ability.can?(action, subject, options)
      end

      # The cannot? methods works just like the can?, except it's the opposite.
      #
      #   cannot? :edit, @project
      #
      # Works in views and controllers.
      def cannot?(action, subject, options = {})
        current_ability.cannot?(action, subject, options)
      end

      # Authorizing in CanCan very neat. You just need a single line inside your helpers:
      #
      #     def '/admin' do
      #       authorize! :admin, :all
      #
      #       haml :admin
      #     end
      #
      # If the user isn't authorized, your app will return a RESTful 403 error, but you can also instruct it to redirect to other pages by defining this setting at your Sinatra configuration.
      #
      #     set :not_auth, '/login'
      # 
      # Or directly in the authorize! command itself:
      #
      #     authorize! :admin, :all, :not_auth => '/login'
      #
      def authorize!(action, subject, options = {})
        if current_ability.cannot?(action, subject, options)
          redirect options[:not_auth] || settings.not_auth || error(403)
        end
      end

      # load_and_authorize is one of CanCan's greatest features. It will, if applicable, load a model based on the :id parameter, and authorize, according to the HTTP Request Method.
      # 
      # The usage in Sinatra is a bit different, since it's implemented from scratch. It is compatible with ActiveRecord, DataMapper and Sequel.
      #
      #     get '/projects/:id' do
      #       load_and_authorize! Project
      #       @project.name
      #     end
      #
      # It is also implemented as a handy condition:
      #
      #     get '/projects/:id', :model => Project do
      #       @project.name
      #     end
      #
      # Authorization also happens automatically, depending on the HTTP verb. Here's the CanCan actions for each verb:
      # 
      # - :list (get without an :id)
      # - :view (get)
      # - :create (post)
      # - :update (put or patch)
      # - :delete (delete)
      def load_and_authorize!(model)
        model = model.class unless model.is_a? Class
        instance = current_instance(params[:id], model) if params[:id]

        authorize! current_operation, instance || model
      end

      protected

      def current_ability
        @current_ability ||= LocalAbility.new(current_user) if LocalAbility.include?(CanCan::Ability)
        @current_ability ||= ::Ability.new(current_user)
      end

      def current_user
        @current_user ||= instance_eval(&self.class.current_user_block) if self.class.current_user_block
      end

      def current_instance(id, model)
        instance ||= model.find_by_id(id) if model.respond_to? :find_by_id   # ActiveRecord
        instance ||= model.get(id) if model.respond_to? :get                 # DataMapper
        instance ||= model[id] if model.superclass.to_s == 'Sequel::Model'   # Sequel
        error 404 unless instance
        instance_name = model.name.gsub(/([a-z\d])([A-Z])/,'\1_\2').downcase
        self.instance_variable_set("@#{instance_name}", instance)
        instance
      end

      def current_operation
        case env["REQUEST_METHOD"]
          when 'GET' then params[:id] ? :read : :list
          when 'POST' then :create
          when 'PUT' then :update
          when 'PATCH' then :update
          when 'DELETE' then :destroy
        end
      end
    end

    # Use this block to pass the current user to CanCan. You have access to all Sinatra variables inside it.
    #
    #   user do
    #     User.find(:id => session[:id])
    #   end
    def user(&block)
      @current_user_block = block
    end

    # Contains the Ability object
    LocalAbility = Class.new

    # Use this block to create abilities. You can use the same syntax as in CanCan:
    #
    #   ability do |user|
    #     can :delete, Article do |article|
    #       article.creator == user
    #     end
    #     can :edit, Article
    #   end
    def ability(&block)
      LocalAbility.send :include, CanCan::Ability
      LocalAbility.send :define_method, :initialize, &block
    end

    def current_user_block
      @current_user_block
    end

    def self.registered(app)
      app.set(:can)   { |action, subject| condition { authorize!(action, subject) } }
      app.set(:model) { |subject| condition { load_and_authorize!(subject) } }
      app.set(:not_auth, nil)
      app.helpers Helpers
    end
  end

  register Can
end
