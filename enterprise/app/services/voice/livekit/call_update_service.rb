# hoichoi: the voice worker reports how a LiveKit call ended.
#
# Status goes through Voice::CallStatus::Manager so a terminal status is never
# overwritten, and the call bubble is refreshed the same way Twilio/WhatsApp do it.
class Voice::Livekit::CallUpdateService
  OUTCOME_LABELS = { 'handoff' => 'ai-handoff', 'overnight' => 'overnight', 'dnc' => 'dnc' }.freeze

  pattr_initialize [:call!, :params!]

  def perform
    ActiveRecord::Base.transaction do
      update_status
      update_call
      update_conversation
    end
  end

  private

  def update_status
    return if params[:status].blank?

    Voice::CallStatus::Manager.new(call: call).process_status_update(params[:status], duration: params[:duration_seconds]&.to_i)
    Voice::CallMessageBuilder.new(call).update_status!(status: call.status, duration_seconds: call.duration_seconds)
  end

  def update_call
    attrs = {}
    attrs[:transcript] = params[:transcript] if params.key?(:transcript)
    attrs[:end_reason] = params[:outcome] if params[:outcome].present?
    call.recording_key = params[:recording_key] if params[:recording_key].present?
    call.update!(attrs.merge(meta: call.meta))
  end

  def update_conversation
    conversation = call.conversation
    outcome = params[:outcome].presence
    extra = { 'call_outcome' => outcome, 'call_reason' => params[:reason].presence }.compact
    conversation.update!(custom_attributes: conversation.custom_attributes.merge(extra)) if extra.any?
    conversation.add_labels(['voice', OUTCOME_LABELS[outcome]].compact)
  end
end
