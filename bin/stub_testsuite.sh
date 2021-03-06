#!/bin/bash
#############################################################################
#
#   stub_testsuite.sh
#
#############################################################################

declare -r SPLITTER='#-----------------------------------------------------------------------------------------'

#----------------------------------------------------------------------------
function stub_testsuite.usage()
{
cat << EOF

Usage:
   "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/$( basename "${BASH_SOURCE[0]}" )" <options> bash_library

where options may be one of:
      gen | -g | --g | --gen      generate a TestSuite containing stub tests for all of the functions in the provided 'bash_library'
     help | -h | --h | --help     this text
     scan | -s | --s | --scan     use the provided 'bash_library' to determine its test suite, then analyze the test suite to determine
                                  what functions have been tested, what still have to be tested, and what redundant tests exist (if any)

EOF
}

#----------------------------------------------------------------------------
function stub_testsuite.createFile()
{
    local -r file_under_test=${1:?"Input parameter 'file_under_test' must be passed to 'function ${FUNCNAME[0]}()'"}
    local -r test_file=${2:?"Input parameter 'test_file' must be passed to 'function ${FUNCNAME[0]}()'"}

    printf '\nGenerating test suite file: %s\n' "$test_file"
    [ -e "$test_file" ] && mv "$test_file" "${test_file}.sav"

    local namespace="$( stub_testsuite.nameSpace "$test_file" )"

cat << EOF > "$test_file"
#!/usr/bin/env bash_unit
${SPLITTER}
#
#  test suite for <devops-scripts>/bashlibs/$(basename "$file_under_test")
#
#  You may need to change the behavior of some commands to create conditions for your code under test
#  to behave as expected. The *fake* function may help you to do that, see documentation.
#
# Organization of this test suite
# ===============================
# test methods
# standard test framework routines
# custom support provided within this suite
#
#
# standard test framework routines              custom support provided within this suite
# --------------------------------              -----------------------------------------
# setup_suite()                                 __${namespace}.mktemp()
# teardown_suite()                              __${namespace}.mock_logger()
# setup()                                       export ${namespace}_LOG_file
# teardown()                                    export ${namespace}_UT_TEST_DIR
#                                               export ${namespace}_DEBUG
#
#
# bash_unit supports several shell oriented assertion functions.
# --------------------------------------------------------------
# fail()
# assert()
# assert_fail()
# assert_status_code()
# assert_equals()
# assert_not_equals()
# fake()
#    Using stdin
#    Using a function
#    fake parameters
#
##########################################################################################
EOF
}

#----------------------------------------------------------------------------
function stub_testsuite.custom_support()
{
    local -r test_file=${1:?"Input parameter 'test_file' must be passed to 'function ${FUNCNAME[0]}()'"}
    local namespace="$( stub_testsuite.nameSpace "$test_file" )"

    echo '  adding: custom support'
    echo "    __${namespace}.mktemp"
    echo "    __${namespace}.mock_logger"
    echo '    exports'
cat << EOF >> "$test_file"

##########################################################################################
#
# custom support
#
##########################################################################################

# custom mktemp to create folder withing the temp storage location for this test
__${namespace}.mktemp() {
    mktemp --tmpdir="\$${namespace}_UT_TEST_DIR" "\$@" 2>/dev/null
}
export -f __${namespace}.mktemp

# MOCK logger implementation
__${namespace}.mock_logger() {
    printf '%s\n' "\$@" >> "\$${namespace}_LOG_file"
}
export -f __${namespace}.mock_logger

export ${namespace}_LOG_file
export ${namespace}_UT_TEST_DIR
export ${namespace}_DEBUG=0

##########################################################################################
EOF
}

#----------------------------------------------------------------------------
function stub_testsuite.die()
{
    local status=$?
    [[ $status -ne 0 ]] || status=255

    printf '\n\x1b[31mFATAL ERROR: %s\x1b[0m\n' "$*" >&2
    exit $status
}

#----------------------------------------------------------------------------
function stub_testsuite.generateTestFile()
{
    local -r file_under_test=${1:?"Input parameter 'file_under_test' must be passed to 'function ${FUNCNAME[0]}()'"}
    local -r test_file=${2:?"Input parameter 'test_file' must be passed to 'function ${FUNCNAME[0]}()'"}

    stub_testsuite.createFile "$file_under_test" "$test_file"

    local -i test_count=0
    for function_name in $(stub_testsuite.getFunctionNames "$file_under_test"); do
        stub_testsuite.test_stub "$test_file" "$function_name"
        (( test_count++ ))
    done

    stub_testsuite.setup_suite "$test_file"
    stub_testsuite.teardown_suite "$test_file"
    stub_testsuite.setup "$test_file"
    stub_testsuite.teardown "$test_file"
    stub_testsuite.custom_support "$test_file"

    printf '\n%d tests generated\n' ${test_count}
}

#----------------------------------------------------------------------------
function stub_testsuite.getFunctionNames()
{
    local -r file_under_test=${1:?"Input parameter 'file_under_test' must be passed to 'function ${FUNCNAME[0]}()'"}

    grep -E '^function\s+.*\s*\(\)\s*\{?$' "$file_under_test" \
    | sed -e 's|function ||' -e 's|(||' -e 's|)||' -e 's|{||' -e 's| ||' \
    | sort
}

#----------------------------------------------------------------------------
function stub_testsuite.getTestNames()
{
    local -r test_file=${1:?"Input parameter 'test_file' must be passed to 'function ${FUNCNAME[0]}()'"}

    grep -E '^test\..+\s*\(\)\s*\{?$' "$test_file" \
    | sed -e 's|test.||' -e 's|(||' -e 's|)||' -e 's|{||' -e 's| ||' \
    | sort
}

#----------------------------------------------------------------------------
function stub_testsuite.main()
{
    local -r fut=${1:?"Input parameter 'fut' must be passed to 'function ${FUNCNAME[0]}()'"}
    local -r test_dir=${2:?"Input parameter 'test_dir' must be passed to 'function ${FUNCNAME[0]}()'"}
    shift ; shift
    local -ra args=( $@ )

    [ -e "$fut" ] || stub_testsuite.die "Test file does not exist"

    # fully qualified name of file_under_test
    local -r file_under_test="$( cd "$( dirname "$fut" )" && pwd )/$( basename "$fut" )"

    printf '\nFile under test:            %s\n' "$file_under_test"

    # test file in test directory. name:  remove extension and prefix with 'test.'
    local -r test_file="${test_dir}/test.$( basename "$fut" )"

    if [ "${#args[*]}" -gt 0 ]; then
        case "${args[0]}" in
            help | -h | --h | --help) stub_testsuite.usage;;
            Help | --Help)            stub_testsuite.usage;;
            HELP | -H | --H | --HELP) stub_testsuite.usage;;
            gen | -g | --g | --gen)   stub_testsuite.generateTestFile "$file_under_test" "$test_file";;
            scan | -s | --s | --scan) stub_testsuite.scanTestFile "$file_under_test" "$test_file";;
            *) echo '..Invalid argument suplied'; stub_testsuite.usage; exit 1;;
        esac
        exit 0
    fi

        echo ''
        echo 'No option to <scan> or <gen> supplied'
    echo ''
    stub_testsuite.usage
        exit 1
}

#----------------------------------------------------------------------------
function stub_testsuite.nameSpace()
{
    local -r test_file=${1:?"Input parameter 'test_file' must be passed to 'function ${FUNCNAME[0]}()'"}

    echo "$( basename "${test_file//./_}" )"
}

#----------------------------------------------------------------------------
function stub_testsuite.scanTestFile()
{
    local -r file_under_test=${1:?"Input parameter 'file_under_test' must be passed to 'function ${FUNCNAME[0]}()'"}
    local -r test_file=${2:?"Input parameter 'test_file' must be passed to 'function ${FUNCNAME[0]}()'"}

    printf '\nTest suite being checked:   %s' "$test_file"

    local -ar functions=( $(stub_testsuite.getFunctionNames "$file_under_test") )
    local -a tests=( $(stub_testsuite.getTestNames "$test_file") )

    printf '\n  %d functions detected' "${#functions[@]}"
    printf ',  %d tests detected' "${#tests[@]}"


    local -a unused=()
    local -i used_count=0
    local -i count=0
    for function_name in "${functions[@]}"; do
        count=0
        for test_name in "${tests[@]}"; do
            [[ "$test_name" =~ ^$function_name ]] && (( count++ ))
        done
        printf '\n    %s:  %d' "$function_name" "$count"
        let used_count=( used_count + count )
        [ "$count" -eq 0 ] && unused+=( "$function_name" )
    done
    printf '\n\n  %d out of %d tests used' "$used_count" "${#tests[@]}"
    if [ "${#unused[@]}" -gt 0 ]; then
        printf '\n  The following functions have no tests: '
        printf '%s ' "${unused[@]}"
    fi

    unused=()
    for test_name in "${tests[@]}"; do
        count=0
        for function_name in "${functions[@]}"; do
            [[ "$test_name" =~ ^$function_name ]] && (( count++ ))
        done
        [ "$count" -eq 0 ] && unused+=( "$test_name" )
    done
    if [ "${#unused[@]}" -gt 0 ]; then
        printf '\n  The following tests are unused:        '
        printf 'test.%s ' "${unused[@]}"
    fi
    echo
}

#----------------------------------------------------------------------------
function stub_testsuite.setup()
{
    local -r test_file=${1:?"Input parameter 'test_file' must be passed to 'function ${FUNCNAME[0]}()'"}
    local namespace="$( stub_testsuite.nameSpace "$test_file" )"

    echo '  adding: setup'
cat << EOF >> "$test_file"

# setup MOCK logger
setup() {
    [ "\$${namespace}_DEBUG" = 0 ] || printf '\x1b[94m%s\x1b[0m\n\n' 'Running setup'
    export LOG=__${namespace}.mock_logger
    fake 'term.log' '__${namespace}.mock_logger "\$FAKE_PARAMS"'
    ${namespace}_LOG_file=\$(__${namespace}.mktemp)
    touch "\$${namespace}_LOG_file"
}
EOF
}

#----------------------------------------------------------------------------
function stub_testsuite.setup_suite()
{
    local -r test_file=${1:?"Input parameter 'test_file' must be passed to 'function ${FUNCNAME[0]}()'"}
    local namespace="$( stub_testsuite.nameSpace "$test_file" )"

    echo '  adding: setup_suite'
cat << EOF >> "$test_file"

##########################################################################################
#
# standard test framework routines
#
##########################################################################################

# load all the bash libraries, setup location for running test_suite,
setup_suite() {

    # create a temp directory for any files etc created by tests
    local -r tmpUserDir="\${TMPDIR:-/tmp}/\$USER"
    mkdir -p "\$tmpUserDir"
    local temporaryDir=\$(mktemp -d --tmpdir="\$tmpUserDir" --suffix=test bash_unit_XXXXXXXXXXXXXXXXXX 2>/dev/null)
    mkdir -p "\$temporaryDir"
    ${namespace}_UT_TEST_DIR="\$temporaryDir"

    # point CBF & CRF to locations in tmp workspace.  Will load libs from there
    export CBF_LOCATION="\$temporaryDir/tmp"            # set CBF_LOCATION for testing
    mkdir -p "\$CBF_LOCATION"
    export CRF_LOCATION="\$temporaryDir/usr/local/crf"  # set CRF_LOCATION for testing
    mkdir -p "\$CRF_LOCATION"

    # pwd is location of test definition file.
    local cbf_location="\$( cd "$( dirname "\${BASH_SOURCE[0]}" )/../.." && pwd )"

    # copy CBF & CRF to workspace
    for dir in 'action.templates' 'cbf' 'project.template' ; do
        cp -r "\${cbf_location}/\${dir}" "\$CBF_LOCATION"
    done

    # now init stuff for testing
    source "\${CBF_LOCATION}/cbf/bin/init.libraries" #> /dev/null
}
EOF
}

#----------------------------------------------------------------------------
function stub_testsuite.teardown()
{
    local -r test_file=${1:?"Input parameter 'test_file' must be passed to 'function ${FUNCNAME[0]}()'"}
    local namespace="$( stub_testsuite.nameSpace "$test_file" )"

    echo '  adding: teardown'
cat << EOF >> "$test_file"

# flush the mock logger
teardown() {
    [ "\$${namespace}_DEBUG" = 0 ] || printf '\x1b[94m%s\x1b[0m\n\n' 'Running teardown'
    [ ! -e "\$${namespace}_LOG_file" ] || rm "\$${namespace}_LOG_file"
    [ \$(ls -A1 "\$${namespace}_UT_TEST_DIR" | wc -l) -eq 0 ] || rm -rf "\$${namespace}_UT_TEST_DIR"/*
}
EOF
}

#----------------------------------------------------------------------------
function stub_testsuite.teardown_suite()
{
    local -r test_file=${1:?"Input parameter 'test_file' must be passed to 'function ${FUNCNAME[0]}()'"}
    local namespace="$( stub_testsuite.nameSpace "$test_file" )"

    echo '  adding: teardownsuite'
cat << EOF >> "$test_file"

# remove anything generated by test suite
teardown_suite() {

    # ensure directory is valid
    [ "\$${namespace}_UT_TEST_DIR" ] || return
    [ "\$${namespace}_UT_TEST_DIR" != '/' ] || return
    [ "\$${namespace}_UT_TEST_DIR" != '~' ] || return
    [ "\$${namespace}_UT_TEST_DIR" != "\$( cd ~ && pwd )" ] || return
    [ "\$${namespace}_UT_TEST_DIR" != "\$TMP" ] || return

    # clean up our junk
    rm -rf "\$${namespace}_UT_TEST_DIR"
}
EOF
}

#----------------------------------------------------------------------------
function stub_testsuite.test_stub()
{
    local -r test_file=${1:?"Input parameter 'test_file' must be passed to 'function ${FUNCNAME[0]}()'"}
    local -r function_name=${2:?"Input parameter 'function_name' must be passed to 'function ${FUNCNAME[0]}()'"}

    printf '    adding test stub for: %s\n' "$function_name"
cat << EOF >> "$test_file"

${SPLITTER}
# provide brief explanation of what test does
test.${function_name}() {
    local expected=0
    local actual=0
#    assert_equals "\$expected" "\$actual"
    fail 'test not implemented'
}
EOF
}

#----------------------------------------------------------------------------

[ $# -ne 0 ] || stub_testsuite.usage
case "$1" in
    -h|-H|--h|--H|-help|--HELP|-Help|--Help) stub_testsuite.usage;;
esac

declare -r TEST_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/test_suites" && pwd )"
declare -r FUT="${1?"Input parameter 'FUT' must be passed to '${BASH_SOURCE[0]}'"}"
shift
stub_testsuite.main "$FUT" "$TEST_DIR" "$@"