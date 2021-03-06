#!/bin/bash

if (( BASH_VERSINFO[0] < 4 )); then
    echo "cmdarg is incompatible with bash versions < 4, please upgrade bash" >&2
    exit 1
fi

CMDARG_ERROR_BEHAVIOR=return

CMDARG_FLAG_NOARG=0
CMDARG_FLAG_REQARG=2
CMDARG_FLAG_OPTARG=4

CMDARG_TYPE_ARRAY='ARRAY'
CMDARG_TYPE_HASH='HASH'
CMDARG_TYPE_STRING='STRING'
CMDARG_TYPE_BOOLEAN='BOOLEAN'
CMDARG_TYPE_SET='SET'

EMPTY_KEY_ALIAS='~'
EMPTY_KEYS_PREFIX='%%'
EMPTY_KEYS=0

function cmdarg
{
    # cmdarg <option> <key> <description> [default value] [validator function]
    #
    # option : The short name (single letter) of the option
    # key : The long key that should be placed into cmdarg_cfg[] for this option
    # description : The text description for this option to be used in cmdarg_usage
    #
    # default value : The default value, if any, for the argument
    # validator : This is passed through eval(), with $OPTARG equal to the current
    #             value of the argument in question, and must return non-zero if
    #             the argument value is invalid. Can be straight bash, but it really
    #             should be the name of a function. This may be enforced in future versions
    #             of the library.
    local shortopt=${1:0:1}
    if [[ "$shortopt" == '~' ]]; then
      shortopt="${EMPTY_KEYS_PREFIX}$((EMPTY_KEYS++))"
    fi
    local key="$2"
    if [[ "$shortopt" == "h" ]]; then
        echo "-h is reserved for cmdarg usage" >&2
        ${CMDARG_ERROR_BEHAVIOR} 1
    fi
    if  [[ "$(type -t cmdarg_$key)" != "" ]] || \
        [[ "${CMDARG_FLAGS[$shortopt]}" != "" ]] || \
        [[ "${CMDARG_TYPES[$key]}" != "" ]]; then
        echo "command line key '$shortopt ($key)' is reserved by cmdarg or defined twice" >&2
        ${CMDARG_ERROR_BEHAVIOR} 1
    fi

    declare -A argtypemap
    argtypemap[':']=$CMDARG_FLAG_REQARG
    argtypemap['?']=$CMDARG_FLAG_OPTARG
    local argtype=${1:1:1}
    if [[ "$argtype" =~ ^[\[{]$ ]]; then
        echo "Flags required [:?] when specifying Hash or Array arguments (${argtype})" >&2
        ${CMDARG_ERROR_BEHAVIOR} 1
    elif [[ "$argtype" != "" ]]; then
        CMDARG_FLAGS[$shortopt]=${argtypemap["$argtype"]}
        if [[ "${1:2:4}" == "[]" ]]; then
            declare -p ${key} >/dev/null 2>&1
            if [[ $? -ne 0 ]]; then
                echo 'Array variable '"${key}"' does not exist. Array variables MUST be declared by the user!' >&2
                ${CMDARG_ERROR_BEHAVIOR} 1
            fi
            CMDARG_TYPES[$key]=$CMDARG_TYPE_ARRAY
        elif [[ "${1:2:4}" == "{}" ]]; then
            declare -p ${key} >/dev/null 2>&1
            if [[ $? -ne 0 ]]; then
                echo 'Hash variable '"${key}"' does not exist. Hash variables MUST be declared by the user!' >&2
                ${CMDARG_ERROR_BEHAVIOR} 1
            fi
            CMDARG_TYPES[$key]=$CMDARG_TYPE_HASH
        else
            CMDARG_TYPES[$key]=$CMDARG_TYPE_STRING
        fi
    else
        CMDARG_FLAGS[$shortopt]=$CMDARG_FLAG_NOARG
        CMDARG_TYPES[$key]=$CMDARG_TYPE_BOOLEAN
        cmdarg_cfg[$key]=false
    fi

    CMDARG["$shortopt"]=$2
    CMDARG_REV["$2"]=$shortopt
    CMDARG_DESC["$shortopt"]=$3
    CMDARG_DEFAULT["$shortopt"]=${4:-}
    CMDARG_LONGOPTS["$shortopt"]="$key"
    if [[ ${CMDARG_FLAGS[$shortopt]} -eq $CMDARG_FLAG_REQARG ]] && [[ "${4:-}" == "" ]]; then
        CMDARG_REQUIRED+=($shortopt)
    else
        CMDARG_OPTIONAL+=($shortopt)
    fi
    cmdarg_cfg["$2"]="${4:-}"
    local validatorfunc
    validatorfunc=${5:-}
    if [[ "$validatorfunc" != "" ]] && [[ "$(declare -F $validatorfunc)" == "" ]]; then
        echo "Validators must be bash functions accepting 1 argument (not '$validatorfunc')" >&2
        ${CMDARG_ERROR_BEHAVIOR} 1
    fi
    CMDARG_VALIDATORS["$shortopt"]="$validatorfunc"
    CMDARG_GETOPTLIST="${CMDARG_GETOPTLIST}$1"
}

function cmdarg_set
{
    shortopt="${EMPTY_KEYS_PREFIX}$((EMPTY_KEYS++))"
    longopt="$1"
    values="$2"
    description="$3"
    CMDARG["$shortopt"]=$longopt
    CMDARG_REV["$longopt"]=$shortopt
    CMDARG_FLAGS["$shortopt"]=${CMDARG_FLAG_NOARG}
    CMDARG_TYPES["$longopt"]="${CMDARG_TYPE_SET}"
    CMDARG_DESC["$shortopt"]="$description"

    CMDARG_SETS["$shortopt"]="$values"
}

function cmdarg_argvs
{
    CMDARG_ARGV=( $@ )
    CMDARG_LENGTH=${#CMDARG_ARGV[@]}
}

function cmdarg_info
{
    # cmdarg_info <flag> <value>
    #
    # Sets various flags about your script that are printed during cmdarg_usage
    #
    local flags="header|copyright|footer|author"
    if [[ ! "$1" =~ $flags ]]; then
        echo "cmdarg_info <flag> <value>" >&2
        echo "Where <flag> is one of $flags" >&2
        ${CMDARG_ERROR_BEHAVIOR} 1
    fi
    CMDARG_INFO["$1"]=$2
}

function cmdarg_describe
{
    local longopt=${CMDARG[$1]}
    local opt=$1
    local argtype=${CMDARG_TYPES[$longopt]}
    local default=${CMDARG_DEFAULT[$opt]}
    local description=${CMDARG_DESC[$opt]}
    local flags="${CMDARG_FLAGS[$opt]}"
    local validator="${CMDARG_VALIDATORS[$opt]}"

    ${cmdarg_helpers['describe']} $longopt $opt $argtype "${default}" "${description}" "${flags}" "${validator}"
}

function cmdarg_describe_default
{
    set -u
    local longopt=$1
    local opt=$2
    local argtype=$3
    local default="$4"
    local description="$5"
    local flags="$6"
    local validator="${7:-}"
    set +u

    local bold=$( echo -e "\033[1m")
    local underline=$( echo -e "\033[4m")
    local normal=$( echo -e "\033[0m")

    if [[ "${opt:0:2}" != '%%' ]]; 
        then optdesc="${bold}-${opt},${normal}"
        else optdesc="   "
    fi
    longoptdesc="${bold}--${longopt}${normal}"

    if [ "${default}" != "" ]; then
        default="\n${bold}${underline}Default${normal}: \"${default}\""
    fi
    local first_line=''
    local second_line=''
    case ${argtype} in
        $CMDARG_TYPE_STRING)
            first_line="${optdesc} ${longoptdesc} <value> : ${underline}String${normal}."
            second_line="${description} ${default}"
            ;;
        $CMDARG_TYPE_SET)
            first_line="${optdesc} ${longoptdesc} : ${underline}Set${normal}."
            second_line="${description} ${default}"
            ;;
        $CMDARG_TYPE_BOOLEAN)
            first_line="${optdesc} ${longoptdesc} : ${underline}Boolean${normal}."
            second_line="${description} ${default}"
            ;;
        $CMDARG_TYPE_ARRAY)
            first_line="${optdesc} ${longoptdesc} <value> [, ...] : ${underline}Array${normal}."
            second_line="${description}.\nPass this argument multiple times for multiple values. ${default}"
            ;;
        $CMDARG_TYPE_HASH)
            first_line="${optdesc} ${longoptdesc} <key=value> {, ..} : ${underline}Hash${normal}."
            second_line="${description}.\nPass this argument multiple times for multiple key/value pairs. ${default}"
            ;;
        *)
            echo "Unable to return string description for ${opt}:${longopt}; unknown type ${argtype}" >&2
            ${CMDARG_ERROR_BEHAVIOR} 1
            ;;
    esac

    local width=$(($(tput cols) - 16))
    second_line=$( echo -e "$second_line" | fold -sw $width | sed 's/^\(.*\)$/                \1/g' )
    local result="\t${first_line}\n${second_line}\n"
    echo -e "$result"
}

function cmdarg_usage
{
    # cmdarg_usage
    #
    # Prints a very helpful usage message about the current program.
    name=$(basename $0)
    if [[ -n ${CMDARG_INFO['author']} ]]; then
        echo "$name ${CMDARG_INFO['copyright']} : ${CMDARG_INFO['author']}"
        echo
    fi
    if [[ -n ${CMDARG_INFO['header']} ]]; then
        echo "${CMDARG_INFO['header']}"
        echo
    fi
    if [[ ${CMDARG_LENGTH} != "" ]]; then
        local argv=""
        for arg in "${CMDARG_ARGV[@]}"; do
          argv="${argv}${arg} "
        done
    fi
    echo -e "Usage: \n        $name [options] $argv"
    echo 

    local key
    if [[ "${#CMDARG_REQUIRED[@]}" -ne 0 ]]; then
        echo "Required Arguments:"
        for key in "${CMDARG_REQUIRED[@]}"
        do
            cmdarg_describe $key
        done
    fi
    if [[ "${#CMDARG_OPTIONAL[@]}" -ne 0 ]]; then
        echo "Optional Arguments":
        for key in "${CMDARG_OPTIONAL[@]}"
        do
            cmdarg_describe $key
        done
    fi
    if [[ "${#CMDARG_SETS[@]}" -ne 0 ]]; then
        echo "Premade sets:"
        for key in "${!CMDARG_SETS[@]}"; do
            cmdarg_describe $key
        done
    fi
    echo
    echo "${CMDARG_INFO['footer']}"
}

function cmdarg_validate
{
    set -u
    local longopt=$1
    local value=$2
    local hashkey=${3:-}
    set +u

    local shortopt=${CMDARG_REV[$longopt]}
    if [ "${CMDARG_VALIDATORS[$shortopt]}" != "" ]; then
        ( ${CMDARG_VALIDATORS[${shortopt}]} "$value" "$hashkey")
        if [ $? -ne 0 ]; then
            echo "Invalid value for -$shortopt : ${value}" >&2
            ${CMDARG_ERROR_BEHAVIOR} 1
        fi
    fi
    return 0
}

function cmdarg_set_opt
{
    set -u
    local key=$1
    local arg="$2"
    set +u

    case ${CMDARG_TYPES[$key]} in
        $CMDARG_TYPE_STRING)
            cmdarg_cfg[$key]=$arg
            cmdarg_validate "$key" "$arg" || ${CMDARG_ERROR_BEHAVIOR} 1
            ;;
        $CMDARG_TYPE_BOOLEAN)
            cmdarg_cfg[$key]=true
            cmdarg_validate "$key" "$arg" || ${CMDARG_ERROR_BEHAVIOR} 1
            ;;
        $CMDARG_TYPE_ARRAY)
            local arrname="${key}"
            local str='${#'"$arrname"'[@]}'
            local prevlen=$(eval "echo $str")
            eval "${arrname}[$((prevlen + 1))]=\"$arg\""
            cmdarg_validate "$key" "$arg" || ${CMDARG_ERROR_BEHAVIOR} 1
            ;;
        $CMDARG_TYPE_HASH)
            local k=${arg%%=*}
            local v=${arg#*=}
            if [[ "$k" == "$arg" ]] && [[ "$v" == "$arg" ]] && [[ "$k" == "$v" ]]; then
                echo "Malformed hash argument: $arg" >&2
                ${CMDARG_ERROR_BEHAVIOR} 1
            fi
            eval "$key[\$k]=\$v"
            cmdarg_validate "$key" "$v" "$k" || ${CMDARG_ERROR_BEHAVIOR} 1
            ;;
        *)
            echo "Unable to return string description for ${key}; unknown type ${CMDARG_TYPES[$key]}" >&2
            ${CMDARG_ERROR_BEHAVIOR} 1
            ;;
    esac
    return 0
}

function cmdarg_check_empty
{
    local key=$1
    local longopt=${CMDARG[$key]}
    local type=${CMDARG_TYPES[$longopt]}

    case $type in
        $CMDARG_TYPE_STRING)
            echo ${cmdarg_cfg[$longopt]}
            ;;
        $CMDARG_TYPE_BOOLEAN)
            echo ${cmdarg_cfg[$longopt]}
            ;;
        $CMDARG_TYPE_ARRAY)
            local arrname="${longopt}"
            local lval='${!'"${arrname}"'[@]}'
            eval "echo $lval"
            ;;
        $CMDARG_TYPE_HASH)
            local arrname="${longopt}"
            local lval='${!'"${arrname}"'[@]}'
            eval "echo $lval"
            ;;
        *)
            echo "${cmdarg_cfg[$longopt]}"
            ;;
    esac
}

declare failed=0
declare missing=""
function cmdarg_parse
{
    # cmdarg_parse "$@"
    #
    # Call it EXACTLY LIKE THAT, and it will parse your arguments for you.
    # This function only knows about the arguments that you previously called 'cmdarg' for.
    if [[ "$1" == "cmdarg_recursive" ]]; then
        local recursive=true
        shift
    fi
    while [[ $# -ne 0 ]]; do
        local optarg=""
        local opt=""
        local longopt=""
        local fullopt=$1
        local is_equals_arg=1

        shift
        if [[ "${fullopt}"  =~ ^(--[a-zA-Z0-9_\-]+|^-[a-zA-Z0-9])= ]]; then
            local tmpopt=$fullopt
            fullopt=${tmpopt%%=*}
            optarg=${tmpopt##*=}
            is_equals_arg=0
        fi

        if [[ "$fullopt" == "--" ]]; then
            cmdarg_argv+=($@)
            break
        elif [[ "${fullopt:0:2}" == "--" ]]; then
            longopt=${fullopt:2}
            opt=${CMDARG_REV[$longopt]}
        elif [[ "${fullopt:0:1}" == "-" ]] && [[ ${#fullopt} -eq 2 ]]; then
            opt=${fullopt:1}
            longopt=${CMDARG[$opt]}
        elif [[ "${fullopt:0:1}" != "-" ]]; then
            cmdarg_argv+=("$fullopt")
            continue
        else
            echo "Malformed argument: ${fullopt}" >&2
            echo "While parsing: $@" >&2
            ${cmdarg_helpers['usage']} >&2
            ${CMDARG_ERROR_BEHAVIOR} 1
        fi

        if [[ "$opt" == "h" ]] || [[ "$longopt" == "help" ]]; then
            ${cmdarg_helpers['usage']} >&2
            ${CMDARG_ERROR_BEHAVIOR} 1
        fi

        if [[ $is_equals_arg -eq 1 ]]; then
            if [[ ${CMDARG_FLAGS[$opt]} -eq ${CMDARG_FLAG_REQARG} ]] || \
                [[ ${CMDARG_FLAGS[$opt]} -eq ${CMDARG_FLAG_OPTARG} ]]; then
                optarg=$1
                shift
            fi
        fi

        if [ ${CMDARG_SETS["${opt}"]+abc} ]; then
            cmdarg_parse "cmdarg_recursive" ${CMDARG_SETS[${opt}]}
        elif [ ${CMDARG["${opt}"]+abc} ]; then
            cmdarg_set_opt "${CMDARG[$opt]}" "$optarg"
            local rc=$?
            failed=$((failed + $rc))
        else
            echo "Unknown argument or invalid value : -${opt} | --${longopt}" >&2
            ${cmdarg_helpers['usage']} >&2
            ${CMDARG_ERROR_BEHAVIOR} 1
        fi
    done

    if [[ -n $recursive ]]; then return 0; fi

    # --- Don't ${CMDARG_ERROR_BEHAVIOR} early during validation, tell the user
    # everything they did wrong first

    local key
    for key in "${CMDARG_REQUIRED[@]}"
    do
        if [[ "$(cmdarg_check_empty $key)" == "" ]]; then
            longopt=${CMDARG_LONGOPTS["${key}"]}
            missing="${missing} --${longopt}(-${key})"
            failed=$((failed + 1))
        fi
    done

    if [[ -z ${recursive} ]] && [[ ${#cmdarg_argv[@]} -ne $CMDARG_LENGTH ]]; then
        error_length=${#cmdarg_argv[@]}
        failed=$((failed + 1))
    fi

    if [ $failed -gt 0 ]; then
        if [[ "$missing" != "" ]]; then
            echo "Missing arguments : ${missing}" >&2
        fi
        if [[ "$error_length" != "" ]]; then
            echo "You must specify ${CMDARG_LENGTH} arguments but specified '${cmdarg_argv[@]}'" >&2
        fi
        echo >&2
        ${cmdarg_helpers['usage']} >&2
        ${CMDARG_ERROR_BEHAVIOR} 1
    fi
}

function cmdarg_traceback
{
    # This code lifted from http://blog.yjl.im/2012/01/printing-out-call-stack-in-bash.html
    local i=0
    local FRAMES=${#BASH_LINENO[@]}
    # FRAMES-2 skips main, the last one in arrays
    for ((i=FRAMES-2; i>=1; i--)); do
        echo '  File' \"${BASH_SOURCE[i+1]}\", line ${BASH_LINENO[i]}, probably in ${FUNCNAME[i+1]} >&2
        # Grab the source code of the line
        sed -n "${BASH_LINENO[i]}{s/^/    /;p}" "${BASH_SOURCE[i+1]}" >&2
    done
    echo "  Error: $LASTERR"
    unset FRAMES
}

function cmdarg_dump
{
    local _key
    local _repr
    local _arrname
    local _keys
    local _idx
    local _ref
    local _value

    for _key in ${!cmdarg_cfg[@]}
    do
        _repr="${_key} : ${CMDARG_TYPES[$_key]}"
        if [[ ${CMDARG_TYPES[$_key]} == $CMDARG_TYPE_ARRAY ]] || [[ ${CMDARG_TYPES[$_key]} == $CMDARG_TYPE_HASH ]] ; then
            _arrname="${_key}"
            echo "${_repr} => "
            _keys='${!'"$_arrname"'[@]}'
            for _idx in $(eval "echo $_keys")
            do
                _ref='${'"$_arrname"'[$_idx]}'
                _value=$(eval "echo $_ref")
                echo "        ${_idx} => $_value"
            done
        else
            echo "${_repr} => ${cmdarg_cfg[$_key]}"
        fi
    done

    echo
    for i in ${!cmdarg_argv[@]}; do
      echo "Arg $i: ${cmdarg_argv[$i]}"
    done
}

function cmdarg_purge
{
    local arrays
    local arr
    arrays="cmdarg_cfg CMDARG CMDARG_REV CMDARG_OPTIONAL CMDARG_REQUIRED"
    arrays="$arrays CMDARG_DESC CMDARG_DEFAULT CMDARG_VALIDATORS CMDARG_INFO"
    arrays="$arrays CMDARG_FLAGS CMDARG_TYPES cmdarg_argv cmdarg_helpers"
    for arr in $arrays
    do
        eval "$arr=()"
    done
    cmdarg_helpers['describe']=cmdarg_describe_default
    cmdarg_helpers['usage']=cmdarg_usage
    CMDARG_GETOPTLIST="h"
}

# Holds the final map of configuration options
declare -xA cmdarg_cfg
# Maps (short arg) -> (long arg)
declare -xA CMDARG
# Maps (long arg) -> (short arg)
declare -xA CMDARG_REV
# A list of optional arguments (e.g., no :)
declare -xa CMDARG_OPTIONAL
# A list of required arguments (e.g., :)
declare -xa CMDARG_REQUIRED
# Maps (set name) -> (values)
declare -xA CMDARG_SETS
# Nesessary cmdarg_argv array
declare -xa CMDARG_ARGV
# Length of nesessary cmdarg_argv array
declare -x CMDARG_LENGTH
# Maps (short arg) -> (description)
declare -xA CMDARG_DESC
# Maps (short arg) -> default
declare -xA CMDARG_DEFAULT
# Maps (short arg) -> validator
declare -xA CMDARG_VALIDATORS
# Miscellanious info about this script
declare -xA CMDARG_INFO
# Map of (short arg) -> flags
declare -xA CMDARG_FLAGS
# Map of (short arg) -> type (string, array, hash)
declare -xA CMDARG_TYPES
# Array of all elements found after --
declare -xa cmdarg_argv
# Hash of functions that are used for user-extensible functionality
declare -xA cmdarg_helpers
declare -xA CMDARG_LONGOPTS
cmdarg_helpers['describe']=cmdarg_describe_default
cmdarg_helpers['usage']=cmdarg_usage

CMDARG_GETOPTLIST="h"
