#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Fix English (Gemini)
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author oleksandr_serdiuk
# @raycast.authorURL https://raycast.com/oleksandr_serdiuk

# Configuration
# To set up your API key, run:
# security add-generic-password -a "raycast" -s "Gemini-API-Key" -w "YOUR_API_KEY"
# Get your API key from: https://aistudio.google.com/apikey
API_KEY=$(security find-generic-password -a "raycast" -s "Gemini-API-Key" -w)
SYSTEM_PROMPT="Please fix my English text without adding quotes. If I use short forms of words like env or prod, leave them unchanged. Return only the corrected text, nothing else."
MODEL="gemini-2.5-flash"

gemini_request() {
  local input_text="$1"

  # Construct JSON payload using jq
  local payload
  payload=$(jq -n \
    --arg system_message "$SYSTEM_PROMPT" \
    --arg user_message "$input_text" \
    '{
      systemInstruction: {
        parts: [{ text: $system_message }]
      },
      contents: [
        {
          parts: [{ text: $user_message }]
        }
      ]
    }')

  # Query Gemini API
  local response
  response=$(curl -s -X POST "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent" \
    -H "Content-Type: application/json" \
    -H "x-goog-api-key: $API_KEY" \
    -d "$payload")

  # Extract the response content
  echo "$response" | jq -r '.candidates[0].content.parts[0].text'
}

# Get the bundle identifier of the frontmost app (more reliable than process name)
CURRENT_APP=$(osascript -e 'tell application "System Events" to return bundle identifier of first application process whose frontmost is true')

# Get clipboard content
CONTENT=$(pbpaste)

# Ensure clipboard is not empty
if [[ -z "$CONTENT" ]]; then
  echo "Clipboard is empty. Copy text and try again."
  exit 1
fi

FIXED_TEXT=$(gemini_request "$CONTENT")

if [[ -n "$FIXED_TEXT" && "$FIXED_TEXT" != "null" ]]; then
  # Copy the result to the clipboard
  printf '%s' "$FIXED_TEXT" | pbcopy
  echo "Fixed and copied!"
else
  echo "Failed to get a valid response from Gemini."
fi

if [[ -n "$CURRENT_APP" ]]; then
  osascript -e "tell application id \"$CURRENT_APP\" to activate" 2>/dev/null
fi
