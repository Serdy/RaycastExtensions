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
API_KEY=$(security find-generic-password -a "raycast" -s "Gemini-API-Key" -w 2>/dev/null)
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

  # Query Gemini API, keeping the HTTP status on the last line
  local response
  response=$(curl -s -w $'\n%{http_code}' -X POST "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent" \
    -H "Content-Type: application/json" \
    -H "x-goog-api-key: $API_KEY" \
    -d "$payload") || { echo "Network error calling Gemini." >&2; return 1; }

  local http_code=${response##*$'\n'}
  local body=${response%$'\n'*}

  if [[ "$http_code" != "200" ]]; then
    echo "Gemini error $http_code: $(jq -r '.error.message // "unknown error"' <<<"$body")" >&2
    return 1
  fi

  # Concatenate every text part (2.5 models can split the answer)
  local text
  text=$(jq -r '[.candidates[0].content.parts[]?.text] | join("")' <<<"$body")

  if [[ -z "$text" ]]; then
    echo "Gemini returned no text (finishReason: $(jq -r '.candidates[0].finishReason // "none"' <<<"$body"))." >&2
    return 1
  fi

  printf '%s' "$text"
}

# Get the bundle identifier of the frontmost app (more reliable than process name)
CURRENT_APP=$(osascript -e 'tell application "System Events" to return bundle identifier of first application process whose frontmost is true')

restore_app() {
  if [[ -n "$CURRENT_APP" ]]; then
    osascript -e "tell application id \"$CURRENT_APP\" to activate" 2>/dev/null
  fi
}

if [[ -z "$API_KEY" ]]; then
  restore_app
  echo 'No API key in Keychain. Run: security add-generic-password -a "raycast" -s "Gemini-API-Key" -w "YOUR_KEY"'
  exit 1
fi

# Get clipboard content
CONTENT=$(pbpaste)

# Ensure clipboard is not empty
if [[ -z "$CONTENT" ]]; then
  restore_app
  echo "Clipboard is empty. Copy text and try again."
  exit 1
fi

# Merge stderr in so the real reason reaches the Raycast HUD
if ! FIXED_TEXT=$(gemini_request "$CONTENT" 2>&1); then
  restore_app
  echo "$FIXED_TEXT"
  exit 1
fi

printf '%s' "$FIXED_TEXT" | pbcopy
restore_app
echo "Fixed and copied!"
