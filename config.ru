# frozen_string_literal: true

require_relative "loader"

clover_freeze

run((Config.development? || Config.e2e_test?) ? Unreloader : Clover.freeze.app)

Tilt.finalize! unless Config.development? || Config.e2e_test?
