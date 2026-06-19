---
name: openai-realtime-api
description: OpenAI Realtime API integration — correct endpoints, session types, WebSocket config, and common pitfalls. Use when working with transcription, audio streaming, or realtime AI features.
---

# OpenAI Realtime API Integration

Reference for implementing OpenAI Realtime API features in BerryShot. Prevents the most common integration errors.

## Two Session Types (Cannot Be Mixed)

| Type | Use Case | Endpoint |
|------|----------|----------|
| `transcription` | Speech-to-text only (mic → text) | `POST /v1/realtime/client_secrets` |
| `realtime` | Full AI conversation (audio in/out, function calling) | `POST /v1/realtime/client_secrets` |

**Critical**: API rejects cross-type updates. A transcription session cannot receive realtime session updates and vice versa.

## Correct Flow: Transcription Sessions

### Step 1: Create Session (REST)

```bash
curl -X POST https://api.openai.com/v1/realtime/client_secrets \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "session": {
      "type": "transcription",
      "audio": {
        "input": {
          "format": {"type": "audio/pcm", "rate": 24000},
          "transcription": {"model": "gpt-realtime-whisper", "language": "vi"}
        }
      }
    }
  }'
```

Response: `{"value": "ek_...", "expires_at": ..., "session": {...}}`

- `value` is the ephemeral key (NOT a WebSocket URL)
- `language`: use ISO code ("vi", "en", "ja") or omit/null for auto-detect

### Step 2: Connect WebSocket

```
wss://api.openai.com/v1/realtime
Authorization: Bearer <ephemeral_key>
```

**Do NOT include `?model=` query parameter** — error: "you must not provide a model parameter for transcription session"

### Step 3: Handle Events

- Transcription sessions: `conversation.item.input_audio_transcription.delta` / `.completed`
- Realtime sessions: `response.output_audio_transcript.*`

## Correct Flow: Realtime Sessions

```bash
curl -X POST https://api.openai.com/v1/realtime/client_secrets \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "session": {
      "type": "realtime",
      "model": "gpt-realtime",
      "audio": {
        "input": {"format": {"type": "audio/pcm", "rate": 24000}},
        "output": {"format": {"type": "audio/pcm", "rate": 24000}}
      },
      "output_modalities": ["audio", "text"]
    }
  }'
```

## Common Errors and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `Invalid URL (POST /v1/realtime/transcription_sessions)` | Endpoint doesn't exist | Use `POST /v1/realtime/client_secrets` |
| `Invalid URL (POST /v1/realtime/sessions)` | Endpoint doesn't exist | Use `POST /v1/realtime/client_secrets` |
| `missing required parameter: session.type` | Missing `"type": "transcription"` or `"type": "realtime"` | Add type to session config |
| `unknown parameter: session.modalities` | Wrong field name | Use `output_modalities` (not `modalities`) |
| `unknown parameter: session.input_audio_format` | Flat config not supported | Nest under `audio.input.format` |
| `unknown parameter: session.input_audio_transcription` | Wrong nesting level | Use `audio.input.transcription` (nested) |
| `passing a transcription session update to a realtime session` | Cross-type update | Match update type to session type |
| `gpt-realtime-whisper is a transcription model` | Whisper used as realtime model | Use `gpt-realtime` for realtime, `gpt-realtime-whisper` only in transcription config |
| `you must not provide a model parameter for transcription session` | `?model=` in WebSocket URL | Remove query param; model is set in `client_secrets` body |

## Model IDs (2025+)

- **Realtime**: `gpt-realtime`, `gpt-realtime-mini`, `gpt-realtime-2`
- **Transcription**: `gpt-realtime-whisper`, `gpt-realtime-translate`
- **Deprecated**: `gpt-4o-realtime-preview`, `gpt-4o-mini-realtime-preview`

## Audio Config Nesting (GA Format)

```
session.audio.input.format      (NOT session.input_audio_format)
session.audio.input.transcription (NOT session.input_audio_transcription)
session.audio.input.turn_detection
session.audio.output.format
session.output_modalities        (NOT session.modalities)
```

## Whisper-Specific Notes

- Whisper models don't support server VAD — need manual `input_audio_buffer.commit` for transcription
- For real-time transcription, commit audio buffers every ~1.5s

## Swift Implementation Reference

Key files in BerryShot:
- `Sources/AI/OpenAIRealtimeProvider.swift` — Transcription provider using `/v1/realtime/client_secrets` + ephemeral key
- `Sources/AI/LiveTranscriptionService.swift` — Audio engine + device change monitoring
- `Sources/AI/RealtimeTranscriptionProvider.swift` — Provider abstraction

## Before Reporting Success

1. Test API endpoint with `curl` first
2. Verify response format matches expected structure
3. Confirm WebSocket connects without `?model=` parameter
4. Check that transcription events arrive (`conversation.item.input_audio_transcription.*`)
