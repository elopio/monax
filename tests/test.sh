#!/usr/bin/env bash

# ----------------------------------------------------------------------------
# Set definitions and defaults

# Where are the Things
base=github.com/eris-ltd/eris-cli
if [ "$CIRCLE_BRANCH" ]
then
  repo=${GOPATH%%:*}/src/github.com/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}
  circle=true
else
  repo=$GOPATH/src/$base
  circle=false
fi
branch=${CIRCLE_BRANCH:=master}
branch=${branch/-/_}

# Docker Backend Versions Eris Tests Against -- Final element in this array is the definitive one.
#   Circle passes or fails based on it. To speed testing uncomment out the second line to override
#   the array and just test against the authoritative one. If testing against a specific backend
#   then change the authoritative one to use that. We define "authoritative" to mean "what docker
#   installs by default on Linux"
declare -a docker_versions17=( "1.7.1" )
declare -a docker_versions18=( "1.8.0" "1.8.1" )
# declare -a docker_versions18=( "1.8.1" )

# Primary swarm of backend machines -- uncomment out second line to use the secondary swarm
#   if/when the primary swarm is either too slow or non-responsive. Swarms here are really
#   data centers. These boxes are on Digital Ocean.
swarm_prim="ams3"
swarm_back="nyc2"
swarm=$swarm_prim
if [[ $1 == "sec_swarm" ]]
then
  swarm="nyc2"
fi

# Define now the tool tests within the Docker container will be booted from docker run
entrypoint="/home/eris/test_tool.sh"
testimage=eris/eris
testuser=eris
remotesocket=2376
localsocket=/var/run/docker.sock
machine_definitions=matDef

# ----------------------------------------------------------------------------
# Check swarm and machine stuff

set_machine() {
  echo "eris-test-$swarm-$ver"
}

check_swarm() {
  machine=$(set_machine)

  if [[ $(docker-machine status $machine) == "Running" ]]
  then
    echo "Machine Running. Switching Swarm."
    if [[ "$swarm" == "$swarm_back" ]]
    then
      swarm=$swarm_prim
    else
      swarm=$swarm_back
    fi

    machine=$(set_machine)
    if [[ $(docker-machine status $machine) == "Running" ]]
    then
      echo "Backup Swarm Machine Also Running."
      return 1
    fi
  else
    echo "Machine not Running. Keeping Swarm."
    machine=$(set_machine)
  fi
}

reset_swarm() {
  swarm=$swarm_prim
}

# ----------------------------------------------------------------------------
# Define how tests will run

runTests(){
  if [[ $1 == "local" ]]
  then
    machine="eris-test-local"
    swarm=solo
    ver=$(docker version | grep "Client version" | cut -d':' -f2 | sed -e 's/^[[:space:]]*//')

    # Note NEVER do this in circle. It will explode.
    echo -e "Starting Eris Docker container.\n"
    if [ "$circle" = false ]
    then
      if [[ $(uname -s) == "Linux" ]]
      then
        docker run --rm --volumes-from $machine_definitions --entrypoint $entrypoint -e MACHINE_NAME=$machine -e SWARM=$swarm -e APIVERSION=$ver -v $localsocket:$localsocket --user $testuser $testimage
      else
        docker run --rm --volumes-from $machine_definitions --entrypoint $entrypoint -e MACHINE_NAME=$machine -e SWARM=$swarm -e APIVERSION=$ver -p $remotesocket --user $testuser $testimage
      fi
    else
      echo "Don't run local in Circle environment."
    fi

    # logging the exit code
    test_exit=$(echo $?)

    # reset the swarm
    reset_swarm
  else
    check_swarm
    if [ $? -ne 0 ]; then return 1; fi

    # Correct for docker build stuff
    if [[ "$branch" == "master" ]]
    then
      branch="latest"
    fi

    # only the last element in the backend array should cause this script to exit with
    #   a non-zero exit code
    echo "Starting Eris Docker container."
    if [[ "$1" == "1.7" ]]
    then
      if [ "$circle" = true ]
      then
        docker run --volumes-from $machine_definitions --entrypoint $entrypoint -e MACHINE_NAME=$machine -e SWARM=$swarm -e APIVERSION=$ver -p $remotesocket --user $testuser $testimage:docker17
      else
        docker run --rm --volumes-from $machine_definitions --entrypoint $entrypoint -e MACHINE_NAME=$machine -e SWARM=$swarm -e APIVERSION=$ver -p $remotesocket --user $testuser $testimage:docker17
      fi
    else
      if [ "$circle" = true ]
      then
        docker run --volumes-from $machine_definitions --entrypoint $entrypoint -e MACHINE_NAME=$machine -e SWARM=$swarm -e APIVERSION=$ver -p $remotesocket --user $testuser $testimage:$branch
      else
        docker run --rm --volumes-from $machine_definitions --entrypoint $entrypoint -e MACHINE_NAME=$machine -e SWARM=$swarm -e APIVERSION=$ver -p $remotesocket --user $testuser $testimage
      fi
    fi

    # logging the exit code
    test_exit=$(echo $?)

    # reset the swarm
    reset_swarm
  fi
}

# ---------------------------------------------------------------------------
# Get the things build and dependencies turned on

echo "Hello! I'm the testing suite for eris."
echo ""
echo "Getting machine definition files sorted."
# suppressed by default as too chatty
if [ "$circle" = true ]
then
  docker run --name $machine_definitions -v $HOME/.docker:/home/eris/.docker erisindustries/test_machines &>/dev/null
else
  docker run --name $machine_definitions erisindustries/test_machines &>/dev/null
fi

echo ""
echo "Building eris in a docker container."
strt=`pwd`
cd $repo
export testimage
export repo
# suppressed by default as too chatty
tests/build_tool.sh > /dev/null
# tests/build_tool.sh
if [ $? -ne 0 ]
then
  echo "Could not build eris. Debug via by directly running [`pwd`/tests/build_tool.sh]"
  exit 1
fi

# ---------------------------------------------------------------------------
# Go!

echo ""
if [[ $1 == "local" ]]
then
  runTests 'local'
else
  if [[ $1 == "all" ]]
  then
    runTests "local"
  fi

  for ver in "${docker_versions17[@]}"
  do
    runTests "1.7"
  done
  for ver in "${docker_versions18[@]}"
  do
    runTests
  done
fi

# ---------------------------------------------------------------------------
# Cleaning up

echo ""
echo ""
echo "Done. Exiting with code: $test_exit"
cd $strt
exit $test_exit
