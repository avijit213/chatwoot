require 'rails_helper'

RSpec.describe 'Voice calls API (LiveKit)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:create_params) { { inbox_id: inbox.id, phone: '+919800000000', provider_call_id: 'call-abc', room_name: 'call-abc' } }

  before { create(:captain_inbox, captain_assistant: assistant, inbox: inbox) }

  describe 'POST /api/v1/accounts/:account_id/voice_calls' do
    it 'rejects a non-administrator' do
      post "/api/v1/accounts/#{account.id}/voice_calls", params: create_params, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'creates a pending conversation, an in-progress livekit call and a call bubble' do
      post "/api/v1/accounts/#{account.id}/voice_calls", params: create_params, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      call = Call.find(response.parsed_body['id'])
      aggregate_failures do
        expect(call.provider).to eq('livekit')
        expect(call.status).to eq('in_progress')
        expect(call.room_name).to eq('call-abc')
        expect(call.conversation.status).to eq('pending')
        expect(call.contact.phone_number).to eq('+919800000000')
        expect(call.message.content_type).to eq('voice_call')
        expect(response.parsed_body['conversation_id']).to eq(call.conversation.display_id)
      end
    end

    it 'is idempotent on provider_call_id' do
      2.times do
        post "/api/v1/accounts/#{account.id}/voice_calls", params: create_params, headers: admin.create_new_auth_token, as: :json
      end

      expect(Call.where(provider_call_id: 'call-abc').count).to eq(1)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/voice_calls/:id' do
    let(:call) do
      Voice::InboundCallBuilder.perform!(inbox: inbox, call_sid: 'call-xyz', provider: :livekit,
                                         caller: { source_ids: ['+919800000001'], contact_attributes: { phone_number: '+919800000001' } })
    end

    it 'ends the call and records transcript, outcome and labels' do
      patch "/api/v1/accounts/#{account.id}/voice_calls/#{call.id}",
            params: { status: 'completed', duration_seconds: 42, transcript: 'hello', recording_key: 'calls/1.ogg', outcome: 'overnight' },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      call.reload
      aggregate_failures do
        expect(call.status).to eq('completed')
        expect(call.duration_seconds).to eq(42)
        expect(call.transcript).to eq('hello')
        expect(call.recording_key).to eq('calls/1.ogg')
        expect(call.end_reason).to eq('overnight')
        expect(call.conversation.custom_attributes['call_outcome']).to eq('overnight')
        expect(call.conversation.label_list).to include('voice', 'overnight')
        expect(call.message.reload.content_attributes.dig('data', 'status')).to eq('completed')
      end
    end

    it 'does not touch calls from other providers' do
      twilio_call = create(:call, account: account, provider: :twilio)

      patch "/api/v1/accounts/#{account.id}/voice_calls/#{twilio_call.id}", params: { status: 'completed' },
                                                                              headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
