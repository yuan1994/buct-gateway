#!/bin/bash
# -------------------------------------------------------------------------------
# Filename:    buct_gateway.sh
# Revision:    1.0
# Date:        2017/02/23
# Author:      tianpian
# Email:       tianpian0805@gmail.com
# Website:     github.com/yuan1994
# Description: buct campus network automatic script
# Notes:       Please read the README
# -------------------------------------------------------------------------------
# Copyright:   2017 (c) tianpian
# License:     Apache-2.0
#
# Please see https://www.apache.org/licenses/LICENSE-2.0
# -------------------------------------------------------------------------------


# ------------ config ---------------

# detect current network is in campus
detectCampusNetworkUrl='http://portal.buct.edu.cn/cas/login'
# detect current network has login
detectIsLoginNetworkUrl='http://www.baidu.com'
# login url
loginUrl='http://202.4.130.95/cgi-bin/srun_portal'
# logout url
logoutUrl="http://202.4.130.95/include/auth_action.php"
# current path
currentPath=$(pwd)
# config file path
configPath="${currentPath}/config.ini"
# saved config path (no use until now)
saveConfigPath="${currentPath}/config-save.ini"
# if the account has login in other place then logout and login in this place
forceLogin="false"
# log file path
logPath="${currentPath}/logs/"
# the daemon progress to login time interval
sleepTime=60
# PID file
PID="$currentPath/buct_gateway.pid"
# arguments for option terminal
argv1=$1

# ------------ function ---------------

# parse json data
parse_json() {
    echo $1 | sed -e 's/[{}\\""]/''/g' | awk -v RS=',' -F: "/^$2/ {print \$2}"
}

# record log
log_write() {
    case $argv1 in
        login|logout|stop|status)
            echo -e $1
            echo -e $2
        ;;
        *)
            if [ ! -d $logPath ]
            then
                mkdir -p $logPath
            fi
            local logFile="${logPath}$(date +%F).log"
            local logLevel=$3
            if [ -z $logLevel ]; then
                logLevel="info"
            fi
            local logContent="[ $(date +"%Y-%m-%d %H:%M:%S") ]\n[ ${logLevel} ] $1 \n data: $2"
            echo -e $logContent >> $logFile
        ;;
    esac
}

# get the url http status code
get_http_code() {
    curl -I -m 5 -o /dev/null -s -w %{http_code} $1
}

# get the url http status
get_http_status() {
    local httpCode=`get_http_code $1`
    if [[ $httpCode -ge 200 && $httpCode -lt 400 ]]; then
        echo "success"
    fi
}

# check username or password is empty
check_account() {
    if [ -z $username ]; then
        read -p "Please enter your student number or job number: " username
    fi
    if [ -z $password ]; then
        read -s -p "Please enter your password: " password
        echo -e ""
    fi
}

# student login
login_account() {
    curl -s -d "action=login&username=${username}&password=${password}&ac_id=1&user_ip=&save_me=1&type=1&n=100&ajax=1&_=1484026877926&callback=json" $loginUrl
}

# load config into variable
load_config_file(){
    if [ -n $(get_config $1 "user" "username") ]; then
        username=$(get_config $1 "user" "username")
    fi
    if [ -n $(get_config $1 "user" "password") ]; then
        password=$(get_config $1 "user" "password")
    fi
    if [ -n $(get_config $1 "conf" "forceLogin") ]; then
        forceLogin=$(get_config $1 "conf" "forceLogin")
    fi
    if [ -n $(get_config $1 "conf" "sleepTime") ]; then
        sleepTime=$(get_config $1 "conf" "sleepTime")
    fi
    if [ -n $(get_config $1 "conf" "loginPath") ]; then
        logPath=$(get_config $1 "conf" "loginPath")
    fi
}

# read config from config files
read_config() {
    if [ -s "/etc/buct-gateway.ini" ]; then
        load_config_file "/etc/buct-gateway.ini"
    fi
    if [ -s $configPath ]; then
        load_config_file $configPath
    fi
    if [ -s $saveConfigPath ]; then
        load_config_file $saveConfigPath
    fi
}

# get config item`s value
get_config() {
    local configFile=$1
	local section=$2
	local item=$3
    local value=`awk -F '=' '/\['${section}'\]/{a=1}a==1&&$1~/'${item}'/{print $2;exit}' $configFile`
    echo $value
}

# set new config into config file
set_config() {
    local configFile=$1
	local section=$2
	local item=$3
	local value=$4
    local result=`sed -i "/^${section}/,/^/ {/^\[${section}/b;/^\[/b;s/^${item}*=.*/${item}=${value}/g;}" $configFile`
    echo $result
}

# usage
usage() {
    echo "Usage: buct_gateway.sh [options] [args...]"
    echo ""
    echo "[ Options ]"
    echo "help               Show usage"
    echo "start              Start the progress and check the network status and automatic login. If you want to start a daemon progress, please use \"buct_gateway.sh start [options] &\" to start a daemon progress"
    echo "stop               Exit the started daemon progress"
    echo "login              Not check the network and direct login"
    echo "logout             Not check the network and direct logout"
    echo ""
    echo "[ Arguments ]"
    echo "  -h               Show usage"
    echo "  -f               If your account has login in other place then logout and login at this place"
    echo "  -u <username>    Set the login or logout account\`s username"
    echo "  -p               Set the login or logout account\`s password"
    echo ""
}

# login
login() {
    check_account
    local loginReturn=`login_account`
    case $(parse_json $loginReturn "ecode") in
        0|"0")
            if [ $(parse_json $loginReturn "error") = "ok" ]; then
                log_write "login success, your ip is: $(parse_json $loginReturn "online_ip")"
            else
                log_write "未知错误0: $(parse_json $loginReturn "error")" $loginReturn "error"
            fi
        ;;
        "E2901")
        echo "帐号或密码错误"
        exit 1
        ;;
        "E2620")
            if [ $forceLogin == "true" ]; then
                local logoutReturn=`logout`
                case $logoutReturn in
                    "网络已断开")
                    login_handle
                    ;;
                    *)
                    log_write $logoutReturn
                    ;;
                esac
            else
                log_write "您的帐号已在线"
            fi
        ;;
        *) log_write "未知错误: $(parse_json $loginReturn "error")" $loginReturn "error"
        ;;
    esac
}

# logout
logout() {
    check_account
    curl -s -d "action=logout&username=${username}&password=${password}&ajax=1" $logoutUrl
}

# start
start() {
    # write current progress id into pid file
    echo $$ > $PID

    # endless loop
    while true ; do
        if [ `get_http_status $detectCampusNetworkUrl` ]; then
            if [ -z `get_http_status $detectIsLoginNetworkUrl` ]; then
                login
            fi
        fi

        sleep $sleepTime
    done
}

# stop
stop() {
    if [ -f $PID ]; then
        {
            kill `cat $PID` > /dev/null
            log_write "progress is stopped"
        } || {
            log_write "progress has not started"
        }
        rm -f $PID
    else
        log_write "progress has not started"
    fi
}

# show network status
status() {
    if [ `get_http_status $detectCampusNetworkUrl` ]; then
        if [ `get_http_status $detectIsLoginNetworkUrl` ]; then
            log_write "your network has been login"
        else
            log_write "you did not login your campus network account"
        fi
    else
        log_write "current network not in campus"
    fi
}

# ------------ run start ---------------

# config options
if [ ${argv1:0:1}!="-" ]; then shift; fi
read_config
while getopts u:f,p,h opt; do
    case "$opt" in
        u) username=$OPTARG
        ;;
        p) read -s -p "Enter your password: " password
        echo -e ""
        ;;
        f) forceLogin="true"
        ;;
        h) usage
        ;;
        *) usage
        ;;
    esac
done

# terminal
case $argv1 in
    start)
        start
    ;;
    stop)
        stop
    ;;
    login)
        login
    ;;
    logout)
        logout
    ;;
    status)
        status
    ;;
    help|*)
        if [ ${argv1:0:1}!="-" ]; then usage; fi
    ;;
esac

exit 0
