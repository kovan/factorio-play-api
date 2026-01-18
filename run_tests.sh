#!/bin/bash
# Run unit tests for factorio-agent-api

cd "$(dirname "$0")"

echo "Running Factorio Agent API unit tests..."
echo ""

lua tests/test_control.lua

exit $?
