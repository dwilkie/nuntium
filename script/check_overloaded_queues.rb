#!/usr/bin/env ruby

require File.expand_path("../../app/models/monit", __FILE__)

Monit.overloaded_queues.any? ? exit(1) : exit(0)
