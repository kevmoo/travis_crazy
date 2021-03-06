#!/bin/bash
source /etc/profile

ANSI_RED="\033[31;1m"
ANSI_GREEN="\033[32;1m"
ANSI_RESET="\033[0m"
ANSI_CLEAR="\033[0K"

TRAVIS_TEST_RESULT=
TRAVIS_CMD=

function travis_cmd() {
  local assert output display retry timing cmd result

  cmd=$1
  TRAVIS_CMD=$cmd
  shift

  while true; do
    case "$1" in
      --assert)  assert=true; shift ;;
      --echo)    output=true; shift ;;
      --display) display=$2;  shift 2;;
      --retry)   retry=true;  shift ;;
      --timing)  timing=true; shift ;;
      *) break ;;
    esac
  done

  if [[ -n "$timing" ]]; then
    travis_time_start
  fi

  if [[ -n "$output" ]]; then
    echo "\$ ${display:-$cmd}"
  fi

  if [[ -n "$retry" ]]; then
    travis_retry eval "$cmd"
  else
    eval "$cmd"
  fi
  result=$?

  if [[ -n "$timing" ]]; then
    travis_time_finish
  fi

  if [[ -n "$assert" ]]; then
    travis_assert $result
  fi

  return $result
}

travis_time_start() {
  travis_timer_id=$(printf %08x $(( RANDOM * RANDOM )))
  travis_start_time=$(travis_nanoseconds)
  echo -en "travis_time:start:$travis_timer_id\r${ANSI_CLEAR}"
}

travis_time_finish() {
  local result=$?
  travis_end_time=$(travis_nanoseconds)
  local duration=$(($travis_end_time-$travis_start_time))
  echo -en "travis_time:end:$travis_timer_id:start=$travis_start_time,finish=$travis_end_time,duration=$duration\r${ANSI_CLEAR}"
  return $result
}

function travis_nanoseconds() {
  local cmd="date"
  local format="+%s%N"
  local os=$(uname)

  if hash gdate > /dev/null 2>&1; then
    cmd="gdate" # use gdate if available
  elif [[ "$os" = Darwin ]]; then
    format="+%s000000000" # fallback to second precision on darwin (does not support %N)
  fi

  $cmd -u $format
}

travis_assert() {
  local result=${1:-$?}
  if [ $result -ne 0 ]; then
    echo -e "\n${ANSI_RED}The command \"$TRAVIS_CMD\" failed and exited with $result during $TRAVIS_STAGE.${ANSI_RESET}\n\nYour build has been stopped."
    travis_terminate 2
  fi
}

travis_result() {
  local result=$1
  export TRAVIS_TEST_RESULT=$(( ${TRAVIS_TEST_RESULT:-0} | $(($result != 0)) ))

  if [ $result -eq 0 ]; then
    echo -e "\n${ANSI_GREEN}The command \"$TRAVIS_CMD\" exited with $result.${ANSI_RESET}"
  else
    echo -e "\n${ANSI_RED}The command \"$TRAVIS_CMD\" exited with $result.${ANSI_RESET}"
  fi
}

travis_terminate() {
  pkill -9 -P $$ &> /dev/null || true
  exit $1
}

travis_wait() {
  local timeout=$1

  if [[ $timeout =~ ^[0-9]+$ ]]; then
    # looks like an integer, so we assume it's a timeout
    shift
  else
    # default value
    timeout=20
  fi

  local cmd="$@"
  local log_file=travis_wait_$$.log

  $cmd &>$log_file &
  local cmd_pid=$!

  travis_jigger $! $timeout $cmd &
  local jigger_pid=$!
  local result

  {
    wait $cmd_pid 2>/dev/null
    result=$?
    ps -p$jigger_pid &>/dev/null && kill $jigger_pid
  } || return 1

  if [ $result -eq 0 ]; then
    echo -e "\n${ANSI_GREEN}The command \"$TRAVIS_CMD\" exited with $result.${ANSI_RESET}"
  else
    echo -e "\n${ANSI_RED}The command \"$TRAVIS_CMD\" exited with $result.${ANSI_RESET}"
  fi

  echo -e "\n${ANSI_GREEN}Log:${ANSI_RESET}\n"
  cat $log_file

  return $result
}

travis_jigger() {
  # helper method for travis_wait()
  local cmd_pid=$1
  shift
  local timeout=$1 # in minutes
  shift
  local count=0

  # clear the line
  echo -e "\n"

  while [ $count -lt $timeout ]; do
    count=$(($count + 1))
    echo -ne "Still running ($count of $timeout): $@\r"
    sleep 60
  done

  echo -e "\n${ANSI_RED}Timeout (${timeout} minutes) reached. Terminating \"$@\"${ANSI_RESET}\n"
  kill -9 $cmd_pid
}

travis_retry() {
  local result=0
  local count=1
  while [ $count -le 3 ]; do
    [ $result -ne 0 ] && {
      echo -e "\n${ANSI_RED}The command \"$@\" failed. Retrying, $count of 3.${ANSI_RESET}\n" >&2
    }
    "$@"
    result=$?
    [ $result -eq 0 ] && break
    count=$(($count + 1))
    sleep 1
  done

  [ $count -gt 3 ] && {
    echo -e "\n${ANSI_RED}The command \"$@\" failed 3 times.${ANSI_RESET}\n" >&2
  }

  return $result
}

travis_fold() {
  local action=$1
  local name=$2
  echo -en "travis_fold:${action}:${name}\r${ANSI_CLEAR}"
}

decrypt() {
  echo $1 | base64 -d | openssl rsautl -decrypt -inkey ~/.ssh/id_rsa.repo
}

# XXX Forcefully removing rabbitmq source until next build env update
# See http://www.traviscistatus.com/incidents/6xtkpm1zglg3
if [[ -f /etc/apt/sources.list.d/rabbitmq-source.list ]] ; then
  sudo rm -f /etc/apt/sources.list.d/rabbitmq-source.list
fi

mkdir -p $HOME/build
cd       $HOME/build


travis_fold start system_info
  echo -e "\033[33;1mBuild system information\033[0m"
  echo -e "Build language: dart"
  if [[ -f /usr/share/travis/system_info ]]; then
    cat /usr/share/travis/system_info
  fi
travis_fold end system_info

echo
echo "options rotate
options timeout:1

nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 208.67.222.222
nameserver 208.67.220.220
" | sudo tee /etc/resolv.conf &> /dev/null
sudo sed -e 's/^\(127\.0\.0\.1.*\)$/\1 '`hostname`'/' -i'.bak' /etc/hosts
sudo sed -e 's/^127\.0\.0\.1\(.*\) localhost \(.*\)$/127.0.0.1 localhost \1 \2/' -i'.bak' /etc/hosts 2>/dev/null
# apply :home_paths
for path_entry in $HOME/.local/bin $HOME/bin ; do
  if [[ ${PATH%%:*} != $path_entry ]] ; then
    export PATH="$path_entry:$PATH"
  fi
done

travis_fold start content_shell_dependencies_install
  echo -e "\033[33;1mInstalling Content Shell dependencies\033[0m"
  sudo sh -c 'echo "deb http://gce_debian_mirror.storage.googleapis.com precise contrib non-free" >> /etc/apt/sources.list'
  sudo sh -c 'echo "deb http://gce_debian_mirror.storage.googleapis.com precise-updates contrib non-free" >> /etc/apt/sources.list'
  sudo sh -c 'apt-get update'
  sudo sh -c 'echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections'
  sudo sh -c 'apt-get install --no-install-recommends -y -q chromium-browser libudev0 ttf-kochi-gothic ttf-kochi-mincho ttf-mscorefonts-installer ttf-indic-fonts ttf-dejavu-core ttf-indic-fonts-core fonts-thai-tlwg msttcorefonts xvfb'
travis_fold end content_shell_dependencies_install

export GIT_ASKPASS=echo

travis_fold start git.checkout
  if [[ ! -d kevmoo/travis_crazy/.git ]]; then
    travis_cmd git\ clone\ --depth\=50\ --branch\=master\ https://github.com/kevmoo/travis_crazy.git\ kevmoo/travis_crazy --assert --echo --retry --timing
  else
    travis_cmd git\ -C\ kevmoo/travis_crazy\ fetch\ origin --assert --echo --retry --timing
    travis_cmd git\ -C\ kevmoo/travis_crazy\ reset\ --hard --assert --echo
  fi
  travis_cmd cd\ kevmoo/travis_crazy --echo
  travis_cmd git\ checkout\ -qf\  --assert --echo
travis_fold end git.checkout

if [[ -f .gitmodules ]]; then
  travis_fold start git.submodule
    echo Host\ github.com'
    '\	StrictHostKeyChecking\ no'
    ' >> ~/.ssh/config
    travis_cmd git\ submodule\ init --assert --echo --timing
    travis_cmd git\ submodule\ update --assert --echo --retry --timing
  travis_fold end git.submodule
fi

rm -f ~/.ssh/source_rsa
export PS4=+
export TRAVIS=true
export CI=true
export CONTINUOUS_INTEGRATION=true
export HAS_JOSH_K_SEAL_OF_APPROVAL=true
export TRAVIS_PULL_REQUEST=false
export TRAVIS_SECURE_ENV_VARS=false
export TRAVIS_BUILD_ID=''
export TRAVIS_BUILD_NUMBER=''
export TRAVIS_BUILD_DIR=$HOME/build/kevmoo/travis_crazy
export TRAVIS_JOB_ID=''
export TRAVIS_JOB_NUMBER=''
export TRAVIS_BRANCH=master
export TRAVIS_COMMIT=''
export TRAVIS_COMMIT_RANGE=''
export TRAVIS_REPO_SLUG=kevmoo/travis_crazy
export TRAVIS_OS_NAME=linux
export TRAVIS_LANGUAGE=dart
export TRAVIS_TAG=''
export TRAVIS_DART_VERSION=stable
echo -e "\033[33;1mDart for Travis-CI is not officially supported, but is community maintained.\033[0m"
echo -e "\033[33;1mPlease file any issues using the following link\033[0m"
echo -e "\033[33;1m  https://github.com/travis-ci/travis-ci/issues/new?labels=community:dart\033[0m"
echo -e "\033[33;1mand mention \`@a14n\`, \`@devoncarew\` and \`@sethladd\` in the issue\033[0m"

travis_fold start dart_install
  echo -e "\033[33;1mInstalling Dart\033[0m"
  travis_cmd curl\ https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-linux-x64-release.zip\ \>\ \$HOME/dartsdk.zip --assert --echo --timing
  travis_cmd unzip\ \$HOME/dartsdk.zip\ -d\ \$HOME\ \>\ /dev/null --assert --echo --timing
  travis_cmd rm\ \$HOME/dartsdk.zip --assert --echo --timing
  travis_cmd export\ DART_SDK\=\"\$HOME/dart-sdk\" --assert --echo --timing
  travis_cmd export\ PATH\=\"\$DART_SDK/bin:\$PATH\" --assert --echo --timing
  travis_cmd export\ PATH\=\"\$HOME/.pub-cache/bin:\$PATH\" --assert --echo --timing
travis_fold end dart_install

travis_fold start content_shell_install
  echo -e "\033[33;1mInstalling Content Shell\033[0m"
  travis_cmd mkdir\ \$HOME/content_shell --assert --echo --timing
  travis_cmd cd\ \$HOME/content_shell --assert --echo --timing
  travis_cmd curl\ https://storage.googleapis.com/dart-archive/channels/stable/release/latest/dartium/content_shell-linux-x64-release.zip\ \>\ content_shell.zip --assert --echo --timing
  travis_cmd unzip\ content_shell.zip\ \>\ /dev/null --assert --echo --timing
  travis_cmd rm\ content_shell.zip --assert --echo --timing
  travis_cmd export\ PATH\=\"\$\{PWD\%/\}/\$\(ls\):\$PATH\" --assert --echo --timing
  travis_cmd cd\ - --assert --echo --timing
travis_fold end content_shell_install

travis_cmd dart\ --version --echo
echo

if [[ -f pubspec.yaml ]]; then
  travis_cmd pub\ get --assert --echo --timing
fi

travis_cmd set\ -e --echo --timing
travis_result $?
travis_cmd which\ dart --echo --timing
travis_result $?
travis_cmd which\ content_shell --echo --timing
travis_result $?
travis_cmd pwd --echo --timing
travis_result $?
travis_cmd ls --echo --timing
travis_result $?
travis_cmd ls\ \$HOME --echo --timing
travis_result $?
travis_cmd echo\ \$PATH --echo --timing
travis_result $?
echo -e "\nDone. Your build exited with $TRAVIS_TEST_RESULT."

travis_terminate $TRAVIS_TEST_RESULT
