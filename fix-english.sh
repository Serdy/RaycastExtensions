#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Spell Chat GPT
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author oleksandr_serdiuk
# @raycast.authorURL https://raycast.com/oleksandr_serdiuk

# # Configuration
# security add-generic-password -a "raycast" -s "ChatGPT-API-Key-Spell" -w "sk-proj-1234567890"
API_KEY=$(security find-generic-password -a "raycast" -s "ChatGPT-API-Key-Spell" -w)
PROMPT="Please fix my English:"
MODEL="gpt-3.5-turbo"

chatgpt_request() {
  local input_text="$1"

  # Escape JSON characters in the input text
  local escaped_content
  escaped_content=$(echo "$input_text" | jq -R '.')

  # Construct JSON payload using jq
  local payload
  payload=$(jq -n \
    --arg model "$MODEL" \
    --arg system_message "$PROMPT" \
    --arg user_message "$input_text" \
    '{
      model: $model,
      messages: [
        { role: "system", content: $system_message },
        { role: "user", content: $user_message }
      ]
    }')

  # Query ChatGPT API
  local response
  response=$(curl -s -X POST "https://api.openai.com/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d "$payload")

  # Extract the response content
  echo "$response" | jq -r '.choices[0].message.content'
}
#############################################
#############################################
#############################################


CURRENT_APP=$(osascript -e 'tell application "System Events" to return name of first application process whose frontmost is true')

# Get clipboard content
CONTENT=$(pbpaste)

# Ensure clipboard is not empty
if [[ -z "$CONTENT" ]]; then
  echo "Clipboard is empty. Copy text and try again."
  exit 1
fi

FIXED_TEXT=$(chatgpt_request "$CONTENT")

if [[ -n "$FIXED_TEXT" && "$FIXED_TEXT" != "null" ]]; then
  # Copy the result to the clipboard
  echo "$FIXED_TEXT" | pbcopy


else
  echo "Failed to get a valid response from ChatGPT. Response: $RESPONSE"
fi
if [[ -n "$CURRENT_APP" ]]; then
  echo "Restoring focus to $CURRENT_APP"
  osascript -e "tell application \"$CURRENT_APP\" to activate"
fi
