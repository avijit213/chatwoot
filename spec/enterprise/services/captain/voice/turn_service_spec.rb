require 'rails_helper'

RSpec.describe Captain::Voice::TurnService do
  let(:account) { create(:account) }
  # Voice inboxes are API inboxes; MessageBuilder only accepts incoming messages there.
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, inbox: inbox, account: account, contact: contact, status: :pending) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:service) { described_class.new(assistant: assistant, conversation: conversation, text: 'amar payment hoyni') }

  before { create(:captain_inbox, captain_assistant: assistant, inbox: inbox) }

  def stub_captain
    allow(Captain::Conversation::ResponseBuilderJob).to receive(:perform_now) do |conv, _assistant|
      yield conv
    end
  end

  def reply(conv, content, sender: assistant, private: false)
    conv.messages.create!(message_type: :outgoing, account: account, inbox: inbox, sender: sender, private: private, content: content)
  end

  it 'answers inline and does not schedule a second Captain job' do
    expect(Captain::Conversation::ResponseBuilderJob).not_to receive(:perform_later)
    stub_captain { |conv| reply(conv, 'Checking now') }

    result = service.perform

    expect(result).to eq(reply: 'Checking now', action: nil, handoff_reason: nil)
    expect(conversation.messages.incoming.last.content_attributes['source']).to eq('voice_turn')
  end

  it 'returns handoff with only the assistant note as the reason' do
    agent = create(:user, account: account)
    stub_captain do |conv|
      reply(conv, 'payment issue', private: true)
      reply(conv, 'Connecting you')
      conv.bot_handoff!
      reply(conv, 'agent secret', sender: agent, private: true)
    end

    result = service.perform

    expect(result).to eq(reply: 'Connecting you', action: 'handoff', handoff_reason: 'payment issue')
  end

  it 'returns resolve when Captain resolves the conversation' do
    stub_captain do |conv|
      reply(conv, 'Done')
      conv.resolved!
    end

    expect(service.perform[:action]).to eq('resolve')
  end

  it 'refuses a conversation a human already owns' do
    conversation.open!

    expect { service.perform }.to raise_error(described_class::NotPending)
  end
end
