# hoichoi: lets the LiveKit voice worker register a call and report its end.
#
# create: contact -> conversation (pending, Topshe first) -> Call(provider: livekit) -> call bubble.
# update: status, transcript, recording key, outcome, labels.
class Api::V1::Accounts::VoiceCallsController < Api::V1::Accounts::EnterpriseAccountsController
  before_action :ensure_administrator
  before_action :set_call, only: :update

  def create
    inbox = Current.account.inboxes.find(params.require(:inbox_id))
    phone = params.require(:phone)
    call = ::Voice::InboundCallBuilder.perform!(
      inbox: inbox,
      call_sid: params.require(:provider_call_id),
      provider: :livekit,
      caller: { source_ids: [phone], contact_attributes: { phone_number: phone, name: phone } },
      extra_meta: { room_name: params[:room_name] }.compact
    )
    render json: { id: call.id, conversation_id: call.conversation.display_id, inbox_id: inbox.id, status: call.status }
  end

  def update
    ::Voice::Livekit::CallUpdateService.new(call: @call, params: update_params).perform
    render json: { id: @call.id, status: @call.reload.status }
  end

  private

  def set_call
    @call = Current.account.calls.livekit.find(params[:id])
  end

  def update_params
    params.permit(:status, :duration_seconds, :transcript, :recording_key, :outcome, :reason)
  end

  # The worker acts for the customer on any inbox; only an administrator token may do that.
  def ensure_administrator
    return if Current.account_user&.administrator?

    render json: { error: 'administrator access required' }, status: :forbidden
  end
end
