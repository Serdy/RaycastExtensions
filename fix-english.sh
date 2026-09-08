#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Fix English
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author oleksandr_serdiuk
# @raycast.authorURL https://raycast.com/oleksandr_serdiuk

# Configuration
# Gemini is tried first; OpenAI is the fallback when Gemini fails (e.g. "User location
# is not supported" behind Cloudflare WARP). Set up the keys with:
# security add-generic-password -a "raycast" -s "Gemini-API-Key" -w "YOUR_API_KEY"
# security add-generic-password -a "raycast" -s "ChatGPT-API-Key-Spell" -w "YOUR_API_KEY"
# Gemini key: https://aistudio.google.com/apikey  OpenAI key: https://platform.openai.com/api-keys
GEMINI_API_KEY=$(security find-generic-password -a "raycast" -s "Gemini-API-Key" -w 2>/dev/null)
OPENAI_API_KEY=$(security find-generic-password -a "raycast" -s "ChatGPT-API-Key-Spell" -w 2>/dev/null)
SYSTEM_PROMPT="Please fix my English text without adding quotes. If I use short forms of words like env or prod, leave them unchanged. Return only the corrected text, nothing else."
GEMINI_MODEL="gemini-2.5-flash"
OPENAI_MODEL="gpt-5.4-nano"

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
  response=$(curl -s -w $'\n%{http_code}' -X POST "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent" \
    -H "Content-Type: application/json" \
    -H "x-goog-api-key: $GEMINI_API_KEY" \
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

openai_request() {
  local input_text="$1"

  local payload
  payload=$(jq -n \
    --arg model "$OPENAI_MODEL" \
    --arg system_message "$SYSTEM_PROMPT" \
    --arg user_message "$input_text" \
    '{
      model: $model,
      reasoning_effort: "none",
      messages: [
        { role: "system", content: $system_message },
        { role: "user", content: $user_message }
      ]
    }')

  local response
  response=$(curl -s -w $'\n%{http_code}' -X POST "https://api.openai.com/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -d "$payload") || { echo "Network error calling OpenAI." >&2; return 1; }

  local http_code=${response##*$'\n'}
  local body=${response%$'\n'*}

  if [[ "$http_code" != "200" ]]; then
    echo "OpenAI error $http_code: $(jq -r '.error.message // "unknown error"' <<<"$body")" >&2
    return 1
  fi

  local text
  text=$(jq -r '.choices[0].message.content // empty' <<<"$body")

  if [[ -z "$text" ]]; then
    echo "OpenAI returned no text." >&2
    return 1
  fi

  printf '%s' "$text"
}

# Try Gemini first, fall back to OpenAI on any Gemini failure
fix_text() {
  local input_text="$1"
  local result gemini_err

  if [[ -n "$GEMINI_API_KEY" ]]; then
    if result=$(gemini_request "$input_text" 2>&1); then
      printf '%s' "$result"
      return 0
    fi
    gemini_err="$result"
  else
    gemini_err="No Gemini API key in Keychain."
  fi

  if [[ -z "$OPENAI_API_KEY" ]]; then
    echo "$gemini_err No OpenAI fallback key in Keychain." >&2
    return 1
  fi

  if result=$(openai_request "$input_text" 2>&1); then
    printf '%s' "$result"
    return 0
  fi

  echo "$gemini_err | Fallback failed: $result" >&2
  return 1
}

# Get the bundle identifier of the frontmost app (more reliable than process name)
CURRENT_APP=$(osascript -e 'tell application "System Events" to return bundle identifier of first application process whose frontmost is true')

restore_app() {
  if [[ -n "$CURRENT_APP" ]]; then
    osascript -e "tell application id \"$CURRENT_APP\" to activate" 2>/dev/null
  fi
}

if [[ -z "$GEMINI_API_KEY" && -z "$OPENAI_API_KEY" ]]; then
  restore_app
  echo 'No API keys in Keychain. Run: security add-generic-password -a "raycast" -s "Gemini-API-Key" -w "YOUR_KEY"'
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
if ! FIXED_TEXT=$(fix_text "$CONTENT" 2>&1); then
  restore_app
  echo "$FIXED_TEXT"
  exit 1
fi

printf '%s' "$FIXED_TEXT" | pbcopy
restore_app
echo "Fixed and copied!"
