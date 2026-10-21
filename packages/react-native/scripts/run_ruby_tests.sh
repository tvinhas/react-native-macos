#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

set -f

basepath=$(dirname "${0}")

# [macOS] These suites need the real CocoaPods gem, Open3 or Pathname, which
# the class mocks in cocoapods/__tests__/test_utils replace, so each one runs
# in its own process.
isolated_pattern='/(maven_mirror_flag|spm)-test\.rb$'

# shellcheck disable=SC2207
files=( $(find . -name '*-test.rb' | grep -Ev "${isolated_pattern}") )
# shellcheck disable=SC2207
isolated_files=( $(find . -name '*-test.rb' | grep -E "${isolated_pattern}") )
# macOS]

test_suite="${basepath}/all_tests.rb"
touch "${test_suite}"

echo "require \"test/unit\"" > "${test_suite}"
echo "discovered the following files:"
for i in "${files[@]}"
do
    filename="${i#"${basepath}/"}"
    echo "${filename}"
    echo "require_relative \"${filename}\"" >> "${test_suite}"
done

ruby -Itest "${test_suite}"
RES=$?
rm "${test_suite}"

# [macOS
for i in "${isolated_files[@]}"
do
    echo "running ${i} in its own process"
    ruby -Itest "${i}" || RES=1
done
# macOS]

exit $RES
