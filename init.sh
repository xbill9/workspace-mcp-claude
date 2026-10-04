#!/bin/bash

# Check if gcloud is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    echo "Error: No active gcloud account found."
    echo "Please run 'gcloud auth login' and try again."
    exit 1
fi

if [ -f "$HOME/project_id.txt" ]; then
    PROJECT_ID=$(cat "$HOME/project_id.txt")
else
    read -p "Enter Project ID: " PROJECT_ID
    echo "$PROJECT_ID" > "$HOME/project_id.txt"
fi

gcloud config set project "$PROJECT_ID"

echo "Using Project ID " $PROJECT_ID

# enable services

gcloud services enable gmail.googleapis.com \
drive.googleapis.com \
docs.googleapis.com \
sheets.googleapis.com \
slides.googleapis.com \
calendar-json.googleapis.com \
chat.googleapis.com \
people.googleapis.com --project=$PROJECT_ID

gcloud services enable gmailmcp.googleapis.com \
	drivemcp.googleapis.com \
	docsmcp.googleapis.com \
	sheetsmcp.googleapis.com \
	slidesmcp.googleapis.com \
	calendarmcp.googleapis.com \
	chatmcp.googleapis.com --project=$PROJECT_ID

cat <<EOF > .env
GOOGLE_GENAI_USE_VERTEXAI=True
GOOGLE_CLOUD_PROJECT=$PROJECT_ID
GOOGLE_CLOUD_LOCATION=us-central1
GENAI_MODEL="gemini-2.5-flash"
EOF

source .env

if [ -z "$CLOUD_SHELL" ]; then
    if ! gcloud auth application-default print-access-token > /dev/null 2>&1; then
        echo "ADC expired or not found. Initializing login..."
        gcloud auth application-default login
    else
        echo "ADC is valid."
    fi
fi

echo "Environment setup"
cat .env

echo "Cloud Login"
gcloud auth list

