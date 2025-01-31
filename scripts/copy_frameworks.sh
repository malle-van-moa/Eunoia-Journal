#!/bin/bash

# Get the path to the original frameworks script
FRAMEWORKS_SCRIPT="${PODS_ROOT}/Target Support Files/Pods-Eunoia-Journal/Pods-Eunoia-Journal-frameworks.sh"

# Create a temporary copy of the script
TEMP_SCRIPT="/tmp/pods_frameworks_$$.sh"
cp "$FRAMEWORKS_SCRIPT" "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# Execute the temporary script
"$TEMP_SCRIPT"
EXIT_CODE=$?

# Clean up
rm -f "$TEMP_SCRIPT"

exit $EXIT_CODE 