require 'cancan'

module Sinatra
  # Sinatra::Can is a lightweight wrapper for CanCan. It contains a partial implementation of the ActiveController helpers.
  module Can
    # Helpers for Sinatra
    module Helpers
      # The can? method receives an action and an object as parameters and checks if the current user is allowed, as declared on the Ability. This method is a helper that can be used inside blocks:
      #
      #   can? :destroy, @project
      #
      # If you haven't instantiated the objects, you can check classes as well:
      # 
      #   can? :create, Project
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

      # Authorization in CanCan is extremely easy. You just need a single line inside your helpers:
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
          session[:return_to] = request.path if settings.auth_use_referrer
          redirect settings.auth_failure_path if !user && settings.auth_failure_path
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
      # You can load collections too, with both syntaxes. Just use a `get` handler, without an `:id` property:
      # 
      #     get '/projects', :model => Project do
      #       # here are your projects
      #       @project
      #     end
      # 
      # Both collection loading and individual entity loading will respect the resource conditions.
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

        if params[:id]
          instance = current_instance(params[:id], model)
        elsif current_operation == :list and model.respond_to? :accessible_by
          collection = current_collection(model)
        end

        authorize! current_operation, instance || model
      end

      protected
      # The main accessor to the warden middleware
      def warden
        request.env['warden']
      end
      # Access the user from the current session
      #
      # @param [Symbol] the scope for the logged in user
      def current_user(scope=nil)
        result = scope ? warden.user(scope) : warden.user
        result
      end

      def current_ability
        @current_ability ||= settings.local_ability.new(current_user) if settings.local_ability.include?(CanCan::Ability)
        @current_ability ||= ::Ability.new(current_user)
      end

      def current_instance(id, model, key = :id)
        instance = CanCan::ModelAdapters::AbstractAdapter.adapter_class(model).find(model, params[:id])
        error 404 unless instance
        self.instance_variable_set("@#{instance_name(model)}", instance)
        instance
      rescue ActiveRecord::RecordNotFound
        error 404
      end

      def current_collection(model)
        collection = model.accessible_by(current_ability, current_operation)
        self.instance_variable_set("@#{instance_name(model)}", collection)
      end

      def instance_name(model)
        model.name.gsub(/([a-z\d])([A-Z])/,'\1_\2').downcase.split("::").last
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

    # Use this block to create abilities. You can use the same syntax as in CanCan:
    #
    #   ability do |user|
    #     can :delete, Article do |article|
    #       article.creator == user
    #     end
    #     can :edit, Article
    #   end
    def ability(&block)
      settings.local_ability.send :include, CanCan::Ability
      settings.local_ability.send :define_method, :initialize, &block
    end

    def self.registered(app)
      app.set(:can)   { |action, subject| condition { authorize!(action, subject) } }
      app.set(:model) { |subject| condition { load_and_authorize!(subject) } }
      app.set(:local_ability, Class.new)
      app.set(:not_auth, nil)
      app.helpers Helpers
    end
  end

  register Can
end
