#!/bin/bash

source /home/user/projects/thirdparty/cmdarg/cmdarg.sh
#source /usr/lib/cmdarg.sh

declare -a array='()'
declare -a array2='()'
declare -A hash='()'

cmdarg_info "header" "Test for parsing parameters library"
cmdarg_info "author" "Me <me@mail.here>"
cmdarg_info "copyright" "(C) 2017"
cmdarg_info "footer" "Made with love"
cmdarg 'r:' 'required-thing' 'Some thing I require. Very very long description that places on few lines'
cmdarg 'R:' 'required-thing-with-default' 'Some thing with default' 'DEFAULT_VALUE'
cmdarg '0?' 'optional-thing' 'Some optional thing'
cmdarg 'b' 'boolean-thing' 'Some boolean thing'
#cmdarg '~:' no-shotkey 'Some thing without shotkey'
cmdarg '~?' no-shotkey2 'Some thing without shotkey' 'default'
cmdarg '~?[]' 'array2' 'Some array'
cmdarg 'a?[]' 'array' 'Some array. \nHas multiline info'
cmdarg 'H?{}' 'hash' 'Some hash'
cmdarg_set 'demo' '-r ddd' 'Set for some magic spells\nUse it carefully'
cmdarg_argvs 'first' 'second'
cmdarg_parse "$@"
if [[ $? != 0 ]]; then exit 1; fi

echo
echo Cmdarg dump: 
cmdarg_dump
echo
