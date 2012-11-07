#!/usr/bin/env bash

script=$1

if [[ "$script" != "rake" ]] && [ $# -lt 2 ] ; then
  echo "Usage:"
  echo "#1" $0 "rake nuntium_rake_task ENV[FOO]=BAR"
  echo "#2" $0 "<script name> <start | stop> <environment> <working group> <instance id>"
  echo "<environment> defaults to production"
  echo "<working group> and <instance id> are optional and passed to the named script if supplied"
  echo "E.g." $0 "generic_worker_daemon_ctl.rb start"
  exit 1
fi

action=$2
environment=$3
working_group=$4
instance_id=$5

# set the default environment to production
: ${environment:="production"}

script_directory=`dirname $0`

nuntium_path=`readlink -f $script_directory/..`

rvmrc_contents=`cat $nuntium_path/.rvmrc`
ruby_version=`echo $rvmrc_contents | sed -e 's/rvm use //'`

#full_ruby_version=`rvm list known_strings | grep ruby-$ruby_version`

if [[ "$script" == "rake" ]] ; then
  /usr/bin/env BUNDLE_GEMFILE=$nuntium_path/Gemfile rvm-shell $ruby_version -c "bundle exec $* -f $nuntium_path/Rakefile"
else
  /usr/bin/env BUNDLE_GEMFILE=$nuntium_path/Gemfile rvm-shell $ruby_version -c "bundle exec ruby $nuntium_path/lib/services/$script $action -- $environment $working_group $instance_id"
fi
