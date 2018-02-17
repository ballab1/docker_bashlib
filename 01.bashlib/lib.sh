#!/bin/bash
#############################################################################
#
#   lib.sh
#
#############################################################################
function lib.buildContainer()
{
    local -r name=${1:?'Input parameter "name" must be defined'}
    local -r timezone=${2:-null}
    export TOOLS=$( lib.getBase )
    
    
    # list of 'notice, directory, action' to perform
    local -A steps=( ['01']='Install_OS_Support 02.packages lib.runScripts'
                     ['02']='Verify_users_and_groups 03.users_groups uidgid.check'
                     ['03']='Download_&_verify_extrenal_packages 04.downloads download.getPackages'
                     ['04']='Install_applications 05.applications lib.runScripts'
                     ['05']='Add_configuration_and_customizations 06.customizations lib.runScripts'
                     ['06']='Make_sure_that_ownership_&_permissions_are_correct 07.permissions lib.runScripts'
                     ['07']='Clean_up 08.cleanup lib.runScripts'
                   )
    
    term.header "$name"
    if [ "$timezone" = null ]; then
        [ -e /etc/TZ ] && export TZ="$( cat /etc/TZ )"
    else
        export TZ="$timezone"
        package.installTimezone "$timezone"
    fi

    # iterate through list
    for id in $( echo "${!steps[@]}" | sort ); do

        # decode list entry into 'notice, directory, action'
        local -a info=( ${steps[$id]} )
        local notice="${info[0]}"
        local dir="${info[1]}"
        local action="${info[2]}"

        # get array of files in directory
        local -a files=( $( lib.getFiles "${TOOLS}/$dir" ) )
        [ ${#files[*]} = 0 ] && continue

        # show notice if there are files to process
        $LOG "${notice//_/ }${LF}" 'task'

        # perform required actions
        if [[ "$timezone" = null && "$dir" = '02.packages' ]]; then
            package.updateIndexes
        fi
        "$action" "${files[*]}"
    done
}

#############################################################################
function lib.getBase()
{
    printf "%s" "$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"   
}

#############################################################################
function lib.getFiles()
{
    local -r dir=${1:?'Input parameter "dir" must be defined'}

    IFS=$'\r\n'
    find "${dir}"  -maxdepth 1 -and ! -name '.*' -and  -type f -or -type l | sort
}

#############################################################################
function lib.indirectReference()
{
    local -r hash=${1:?'Input parameter "hash" must be defined'}
    local -r key=${2:?'Input parameter "key" must be defined'}
    set +o nounset
    local -r default="$3"

    local val=$( eval "echo \${$hash[$key]}" )
    [ -z "$val" ] && val="$default"
    echo "$val"
    set -o nounset
}

#############################################################################
function lib.runScripts()
{
    local -a files=${1:?'Input parameter "files" must be defined'}

    for file in ${files} ; do
        chmod 755 "$file"
        $LOG "..executing ${file}${LF}" 'info'
        eval "$file" || $LOG ">>>>> issue while executing $( basename "$file" ) <<<<<${LF}" 'warn'
    done
}

#############################################################################
