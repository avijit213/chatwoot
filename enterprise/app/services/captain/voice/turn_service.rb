# hoichoi: one synchronous Captain turn for the phone.
#
# The voice worker sends what the caller said and waits for Topshe's reply in the
# same request. It reuses ResponseBuilderJob inline (perform_now) so every
# Captain override (language pin, false-promise guard, handoff messages) applies
# exactly as it does for chat.
#
# The incoming message is tagged `source: voice_turn`; the message hook skips
# Captain scheduling for tagged messages (see HookExecutionService), otherwise
# Sidekiq would answer the same message a second time.
class Captain::Voice::TurnService
  SOURCE = 'voice_turn'.freeze

  class NotPending < StandardError; end

  pattr_initialize [:assistant!, :conversation!, :text!]

  def perform
    raise NotPending unless conversation.pending?

    incoming = create_incoming_message
    Captain::Conversation::ResponseBuilderJob.perform_now(conversation, assistant)
    conversation.reload

    { reply: reply_after(incoming), action: action, handoff_reason: handoff_reason(incoming) }
  end

  private

  def create_incoming_message
    Messages::MessageBuilder.new(
      conversation.contact,
      conversation,
      { content: text, message_type: 'incoming', content_attributes: { 'source' => SOURCE } }
    ).perform
  end

  def reply_after(incoming)
    conversation.messages.outgoing.where(private: false).where('id > ?', incoming.id).order(:id).pluck(:content).compact.join("\n").presence
  end

  def action
    return 'handoff' if conversation.open?
    return 'resolve' if conversation.resolved?

    nil
  end

  # Only the assistant's own note: an agent's private note must never be read aloud or logged as the reason.
  def handoff_reason(incoming)
    return unless conversation.open?

    conversation.messages.where(private: true, sender: assistant).where('id > ?', incoming.id).last&.content
  end
end
