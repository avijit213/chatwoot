require 'rails_helper'

RSpec.describe 'POST /api/v1/accounts/:account_id/captain/assistants/:id/voice_turn', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending) }
  let(:url) { "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/voice_turn" }
  let(:body) { { conversation_id: conversation.display_id, text: 'hello' } }

  it 'rejects a non-administrator' do
    post url, params: body, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns the turn result' do
    turn = instance_double(Captain::Voice::TurnService, perform: { reply: 'hi', action: nil, handoff_reason: nil })
    allow(Captain::Voice::TurnService).to receive(:new).and_return(turn)

    post url, params: body, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('reply' => 'hi', 'action' => nil, 'handoff_reason' => nil)
  end

  it 'returns 409 when a human already owns the conversation' do
    conversation.open!

    post url, params: body, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:conflict)
  end
end
