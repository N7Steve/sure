# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :openai_access_token,
  :client_id, :consumer_key, :snaptrade_user_id, :snaptrade_user_secret,
  :oauth_access_token, :oauth_refresh_token, :code_verifier, :code_challenge,
  # A device code redeems into tokens on its own, so it is a bearer credential in
  # transit; verification_uri_complete embeds the user code, hence all three.
  :device_code, :user_code, :verification_uri_complete,
  :bank_username, :bank_password, :security_answers, :captcha_input
]

# OAuth authorization codes are short-lived bearer credentials. Filter only a
# parameter whose complete key is `code`; adding `:code` above would also hide
# unrelated fields such as country_code and institution_code.
Rails.application.config.filter_parameters << lambda do |key, value|
  value.replace("[FILTERED]") if key.to_s == "code" && value.respond_to?(:replace)
end
