#!/bin/bash

# This script sets various Google Cloud related environment variables.
# It must be SOURCED to make the variables available in your current shell.
# Example: source ./set_env.sh

if [ -z "$CLOUD_SHELL" ]; then
    # Check standard gcloud auth
    if ! gcloud auth print-access-token > /dev/null 2>&1; then
        echo "gcloud auth expired or not found. Initializing login..."
        gcloud auth login
    else
        echo "gcloud auth is valid."
    fi

    # Check Application Default Credentials
    if ! gcloud auth application-default print-access-token > /dev/null 2>&1; then
        echo "ADC expired or not found. Initializing login..."
        gcloud auth application-default login
    else
        echo "ADC is valid."
    fi
fi
