# frozen_string_literal: true

require_relative "model"

require "roda"

class Clover < Roda
  puts "0000000000000000000"
  def self.freeze
    # :nocov:
    unless Config.test?
      puts "1111111111111111111"
      Sequel::Model.freeze_descendents
      puts "1313131313131313131"
      DB.freeze
    end
    # :nocov:
    super
  end

  route do |r|
    puts "212121212121212121"
    subdomain = r.host.split(".").first
    puts "242424242424242424"
    if subdomain == "api"
      r.run CloverApi
    end

    # To make test and development easier
    # :nocov:
    unless Config.production?
      r.on "api" do
        r.run CloverApi
      end
    end
    # :nocov:

    puts "38383838383838383838"
    r.run CloverWeb
  end
end
