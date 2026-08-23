require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in users(:sure_support_staff)
  end

  test "index groups users by family sorted by transaction count" do
    family_with_more = users(:family_admin).family
    family_with_fewer = users(:empty).family

    account = Account.create!(family: family_with_more, name: "Test", balance: 0, currency: "USD", accountable: Depository.new)
    3.times { |i| account.entries.create!(name: "Txn #{i}", date: Date.current, amount: 10, currency: "USD", entryable: Transaction.new) }

    get admin_users_url
    assert_response :success

    body = response.body
    more_idx = body.index(family_with_more.name)
    fewer_idx = body.index(family_with_fewer.name)

    assert_not_nil more_idx
    assert_not_nil fewer_idx
    assert_operator more_idx, :<, fewer_idx,
      "Family with more transactions should appear before family with fewer"
  end

  test "index clearly identifies instance scope, current family, and current user role" do
    get admin_users_url

    assert_response :success
    assert_includes response.body, "Instance-wide administration"
    assert_includes response.body, users(:sure_support_staff).family.name
    assert_includes response.body, "Your family"
    assert_includes response.body, "Super Admin"
    assert_includes response.body, "(You)"
  end

  test "index identifies a family backed by the demo monitoring key as demo data" do
    demo_user = users(:family_admin)
    demo_user.api_keys.create!(
      name: "monitoring",
      key: ApiKey::DEMO_MONITORING_KEY,
      scopes: [ "read" ],
      source: "monitoring"
    )

    get admin_users_url

    assert_response :success
    assert_includes response.body, "Demo data"
  end

  test "index shows subscription status for families" do
    family = users(:family_admin).family
    family.subscription&.destroy
    Subscription.create!(
      family_id: family.id,
      status: :active,
      stripe_id: "cus_test_#{family.id}"
    )

    get admin_users_url
    assert_response :success
    assert_match(/Active/, response.body, "Page should show subscription status for families with active subscriptions")
  end

  test "index shows no subscription label for families without subscription" do
    users(:family_admin).family.subscription&.destroy

    get admin_users_url
    assert_response :success
    assert_match(/No subscription/, response.body, "Page should show 'No subscription' for families without one")
  end

  test "index shows removed SSO identities with a recovery action" do
    block = SsoIdentityBlock.create!(
      provider: "openid_connect",
      uid_digest: SsoIdentityBlock.digest("blocked-subject"),
      identity_label: "removed-user@example.com"
    )

    get admin_users_url

    assert_response :success
    assert_select "form[action=?]", admin_sso_identity_block_path(block)
    assert_match block.identity_label, response.body
  end

  test "super admin permanently removes a user and revokes their credentials" do
    target = users(:family_member)
    target_email = target.email
    removed_identity = target.oidc_identities.first!
    removed_provider = removed_identity.provider
    removed_uid = removed_identity.uid
    target.sessions.create!
    oauth_app = Doorkeeper::Application.create!(
      name: "Removal test",
      redirect_uri: "https://app.example/callback",
      confidential: false
    )
    oauth_token = Doorkeeper::AccessToken.create!(
      application: oauth_app,
      resource_owner_id: target.id,
      scopes: "read_write",
      use_refresh_token: true
    )
    assert target.oidc_identities.exists?
    assert target.api_keys.exists?

    assert_difference -> { SsoAuditLog.by_event("user_removed").count }, 1 do
      assert_enqueued_with(job: UserPurgeJob, args: [ target ]) do
        delete admin_user_url(target), params: { confirmation_text: target_email }
      end
    end

    assert_redirected_to admin_users_path
    target.reload
    assert_not target.active?
    assert_empty target.sessions
    assert_empty target.oidc_identities
    assert_empty target.api_keys
    assert oauth_token.reload.revoked?
    assert SsoIdentityBlock.blocked?(provider: removed_provider, uid: removed_uid)
    identity_block = SsoIdentityBlock.find_by!(provider: removed_provider)
    if SsoIdentityBlock.encryption_ready?
      assert_equal target_email, identity_block.identity_label
    else
      assert_not_equal target_email, identity_block.identity_label
    end
    audit_log = SsoAuditLog.by_event("user_removed").order(:created_at).last
    assert_equal target.id, audit_log.metadata.fetch("target_user_id")
    assert_not audit_log.metadata.key?("target_email")
    assert_equal users(:sure_support_staff).id, audit_log.metadata.fetch("actor_user_id")
  end

  test "super admin cannot remove themselves" do
    me = users(:sure_support_staff)

    assert_no_enqueued_jobs only: UserPurgeJob do
      delete admin_user_url(me)
    end

    assert_redirected_to admin_users_path
    assert User.exists?(me.id)
    assert me.reload.active?
  end

  test "audit failure rolls back user removal" do
    target = users(:family_member)
    target_email = target.email
    SsoAuditLog.expects(:log_user_removed!).raises("audit failure")

    assert_no_enqueued_jobs only: UserPurgeJob do
      assert_raises(RuntimeError, match: /audit failure/) do
        delete admin_user_url(target), params: { confirmation_text: target_email }
      end
    end

    assert target.reload.active?
    assert target.oidc_identities.exists?
  end

  test "inactive super admin cannot use an existing session to remove the last active super admin" do
    target = users(:family_admin)
    target.update!(role: :super_admin)
    User.where(role: :super_admin).where.not(id: target.id).update_all(active: false)

    assert_no_enqueued_jobs only: UserPurgeJob do
      delete admin_user_url(target), params: { confirmation_text: target.email }
    end

    assert_redirected_to new_session_path
    assert User.exists?(target.id)
    assert target.reload.active?
  end

  test "deletion page redirects instead of erroring when targeting yourself" do
    me = users(:sure_support_staff)

    get deletion_admin_user_url(me)

    assert_redirected_to admin_users_path
    assert_match(/cannot remove your own account/i, flash[:alert].to_s)
  end

  test "deletion confirmation requires the target email" do
    target = users(:family_member)

    assert_no_enqueued_jobs only: UserPurgeJob do
      delete admin_user_url(target), params: { confirmation_text: "wrong@example.com" }
    end

    assert_redirected_to admin_users_path
    assert target.reload.active?
  end

  test "deletion page renders a typed email confirmation dialog" do
    target = users(:family_member)

    get deletion_admin_user_url(target)

    assert_response :success
    assert_select "dialog"
    assert_select "input[name=confirmation_text][required]"
    assert_includes response.body, target.email
  end

  test "last family user confirmation names the family and warns about deleting its data" do
    family = Family.create!(name: "Disposable Demo", currency: "USD")
    target = family.users.create!(
      email: "last-demo-user@example.com",
      password: "password123",
      role: :guest
    )
    family.accounts.create!(
      name: "Demo checking",
      balance: 0,
      currency: "USD",
      accountable: Depository.new
    )

    get deletion_admin_user_url(target)

    assert_response :success
    assert_select "input[name=confirmation_text][required]"
    assert_includes response.body, family.name
    assert_includes response.body, "also delete"
    assert_includes response.body, "1 account"
  end

  test "super admin can remove the last family user who owns the protected demo monitoring key" do
    family = Family.create!(name: "Disposable Demo", currency: "USD")
    target = family.users.create!(
      email: "demo-key-owner@example.com",
      password: "password123",
      role: :guest
    )
    demo_key = target.api_keys.create!(
      name: "monitoring",
      key: ApiKey::DEMO_MONITORING_KEY,
      scopes: [ "read" ],
      source: "monitoring"
    )

    assert_enqueued_with(job: UserPurgeJob, args: [ target ]) do
      delete admin_user_url(target), params: { confirmation_text: family.name }
    end

    assert_redirected_to admin_users_path
    assert_equal I18n.t("admin.users.destroy.success"), flash[:notice]
    assert_not ApiKey.exists?(demo_key.id)
    assert_not target.reload.active?

    perform_enqueued_jobs only: UserPurgeJob
    assert_not Family.exists?(family.id)
  end

  test "associated-record removal failures are captured and shown without a server error" do
    target = users(:family_member)
    key = target.api_keys.first!
    error = ActiveRecord::RecordNotDestroyed.new("Could not remove credential", key)
    User.any_instance.stubs(:permanently_remove!).raises(error)

    assert_difference("DebugLogEntry.count", 1) do
      delete admin_user_url(target), params: { confirmation_text: target.email }
    end

    assert_redirected_to admin_users_path
    assert_equal I18n.t("admin.users.destroy.failure"), flash[:alert]
    debug_entry = DebugLogEntry.order(:created_at).last
    assert_equal "user_management", debug_entry.category
    assert_equal key.id, debug_entry.metadata.fetch("record_id")
  end

  test "non super admin cannot remove a user" do
    sign_in users(:family_member)
    target = users(:family_admin)

    assert_no_enqueued_jobs only: UserPurgeJob do
      delete admin_user_url(target)
    end

    assert_redirected_to root_path
    assert User.exists?(target.id)
  end
end
