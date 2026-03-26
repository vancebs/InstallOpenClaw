#! /bin/bash

#############################################
# json
function json_object() {
    # $@ fields
    _fields=$(printf ,%s $@)
    echo "{${_fields:1}}"
}

function json_field_common() {
    # $1: key
    # $2: value
    echo "\"$1\":$2"
}

function json_field_string() {
    # $1: key
    # $2: value
    echo "\"$1\":\"$2\""
}

function json_field_array_common() {
    # $1: key
    # $2: array
    _key=$1
    shift
    _vals=($@)
    _val=$(printf ,%s ${_vals[@]})
    echo "\"$_key\":[${_val:1}]"
}

function json_field_array_string() {
    # $1: key
    # $2: array
    _key=$1
    shift

    # return empty if param count is 0
    if [ $# -eq 0 ]; then
        echo "\"$_key\":[]"
        return
    fi

    _val="\"$1\""
    shift
    while [ $# -gt 0 ]; do
        _val="${_val},\"$1\""
        shift
    done
    echo "\"$_key\":[$_val]"
}

function json_field_array_string_no_empty() {
    # $1: key
    # $2: array
    _key=$1
    shift
    _vals=($@)
    if [ ${#_vals[@]} -gt 0 ]; then
        _val=$(printf ,\"%s\" ${_vals[@]})
    else
        _val=""
    fi
    echo "\"$_key\":[${_val:1}]"
}

function non_empty() {
    # $1 value
    # $2 condition
    if [ "$2:-" != "" ]; then
        echo "$value"
    else
        echo ""
    fi
}

