# frozen_string_literal: true

require 'forwardable'

module Faraday
  # Response represents an HTTP response from making an HTTP request.
  class Response
    # Used for simple response middleware.
    class Middleware < Faraday::Middleware
      def call(env)
        @app.call(env).on_complete do |environment|
          on_complete(environment)
        end
      end

      # Override this to modify the environment after the response has finished.
      # Calls the `parse` method if defined
      def on_complete(env)
        env.body = parse(env.body) if respond_to?(:parse) && env.parse_body?
      end
    end

    extend Forwardable
    extend MiddlewareRegistry

    register_middleware File.expand_path('response', __dir__),
                        raise_error: [:RaiseError, 'raise_error'],
                        logger: [:Logger, 'logger']

    def initialize(env = nil)
      @env = Env.from(env) if env
      @on_complete_callbacks = []
    end

    attr_reader :env

    def status
      finished? ? env.status : nil
    end

    def reason_phrase
      finished? ? env.reason_phrase : nil
    end

    def headers
      finished? ? env.response_headers : {}
    end
    def_delegator :headers, :[]

    def body
      finished? ? env.body : nil
    end

    def finished?
      !!env
    end

    def on_complete(&block)
      if !finished?
        @on_complete_callbacks << block
      else
        yield(env)
      end
      self
    end

    def finish(env)
      raise 'response already finished' if finished?

      @env = env.is_a?(Env) ? env : Env.from(env)
      @on_complete_callbacks.each { |callback| callback.call(@env) }
      self
    end

    def success?
      finished? && env.success?
    end

    def to_hash
      {
        status: env.status, body: env.body,
        response_headers: env.response_headers
      }
    end

    # because @on_complete_callbacks cannot be marshalled
    def marshal_dump
      finished? ? to_hash : nil
    end

    def marshal_load(env)
      @env = Env.from(env)
    end

    # Expand the env with more properties, without overriding existing ones.
    # Useful for applying request params after restoring a marshalled Response.
    def apply_request(request_env)
      raise "response didn't finish yet" unless finished?

      @env = Env.from(request_env).update(@env)
      self
    end
  end
end
