#!/usr/bin/env ruby

require File.expand_path("../../app/models/monit", __FILE__)

raise "Nuntium has overloaded queues!" if Monit.overloaded_queues(:environment => ARGV[0], :rabbitmqctl_path => ARGV[0]).any?
