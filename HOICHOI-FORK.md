# hoichoi fork of Chatwoot: voice

Branch `hoichoi/voice-livekit`, based on tag **`v4.16.2`**, the version prod runs (see
`Hoichoi.Backend/k8s/helm-values/eks-prod/chatwoot.yaml`). Upstream is the `upstream` remote and
`origin` is `avijit213/chatwoot`.

This branch is separate from `hoichoi/widget-theme`. Merge the two into one image branch when both ship.

## Why

The AI voice agent (HOI-3902, repo `avijit213/Hoichoi.VoiceAgentsTemp`) needs two things stock
Chatwoot lacks:

1. **A synchronous Captain turn.** Stock Captain answers through a Sidekiq job, but the phone
   needs Topshe's reply inside the same request.
2. **Calls from our own telephony.** Chatwoot voice supports only Twilio and WhatsApp, and Twilio
   can't terminate Indian PSTN. Our calls come from Exotel through LiveKit.

## What changed

Every change is small and marked with a `hoichoi:` comment.

| File | Change |
|---|---|
| `enterprise/app/services/captain/voice/turn_service.rb` | **new.** Creates the incoming message (tagged `source: voice_turn`), runs `ResponseBuilderJob.perform_now`, returns `{reply, action, handoff_reason}`. `handoff_reason` is taken from the assistant's own private note only. |
| `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb` | `voice_turn` action (+ `set_assistant`); 409 if the conversation isn't pending |
| `enterprise/app/policies/captain/assistant_policy.rb` | `voice_turn?`: administrators only |
| `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb` | skip the Captain schedule for `voice_turn` messages, so Topshe doesn't reply twice |
| `enterprise/app/models/call.rb` | `provider` enum gains `livekit: 2`; `meta` gains `room_name`, `recording_key` |
| `enterprise/app/services/voice/inbound_call_builder.rb` | LiveKit call on a Captain inbox → conversation `pending` (Topshe first) and call `in_progress` (no agent "Accept" popup) |
| `enterprise/app/controllers/api/v1/accounts/voice_calls_controller.rb` | **new.** `POST` registers a call; `PATCH` reports status, transcript, recording key, outcome |
| `enterprise/app/services/voice/livekit/call_update_service.rb` | **new.** Applies the PATCH through `Voice::CallStatus::Manager` and refreshes the bubble; adds labels `voice` / `ai-handoff` / `overnight` / `dnc` |
| `config/routes.rb` | `post :voice_turn`; `resources :voice_calls, only: [:create, :update]` |
| `config/locales/en.yml` | `voice_call.livekit: 'Phone Call'` |
| `spec/enterprise/...` | specs for all of the above |

No migration is needed. `calls.provider` is an integer column, and `meta` is jsonb.

## API

All endpoints need an **administrator** user's `api_access_token`: a dedicated `voice-worker`
user whose token lives in SSM. Agent-bot tokens can't call these endpoints.

```http
POST /api/v1/accounts/:account_id/voice_calls
  { inbox_id, phone, provider_call_id, room_name }
→ { id, conversation_id, inbox_id, status }

POST /api/v1/accounts/:account_id/captain/assistants/:id/voice_turn
  { conversation_id, text }
→ { reply, action: null | "handoff" | "resolve", handoff_reason }     409 if not pending

PATCH /api/v1/accounts/:account_id/voice_calls/:id
  { status, duration_seconds, transcript, recording_key, outcome, reason }
→ { id, status }
```

## Not done yet (next stages)

- Attaching the recording from `recording_key` to `Call#recording` (S3 → ActiveStorage).
- Warm transfer: the LiveKit token and conference services, a webhook controller, and dashboard
  `livekitVoiceClient.js`. Until then, the call bubble shows status only; there is no Join button
  for LiveKit calls.
- Forwarding the `X-Voice-Caller` identity from `Captain::CustomTool`.

## Deploying

Prod runs the stock `chatwoot/chatwoot:v4.16.2` image today. To run this branch:
1. build and push an image from it to ECR;
2. point `image.repository`/`tag` in `helm-values/eks-*/chatwoot.yaml` at that image;
3. keep the existing ConfigMap-mounted initializers (`captain_llm_overrides.rb`,
   `hoichoi_phone_normalize.rb`). They're unrelated and keep working.

We then own security patching: rebase onto each upstream release tag.
