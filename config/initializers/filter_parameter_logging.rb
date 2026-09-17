# frozen_string_literal: true

Rails.application.config.filter_parameters += %i[password token otp_attempt passw secret token _key crypt salt
                                                 certificate otp ssn file cvv cvc]

# Pilot bearer credentials are header-only. Filter these names anyway so an
# accidental query/body use cannot expose tokens or verifier material in logs.
Rails.application.config.filter_parameters += %i[
  access_token authorization code nonce refresh_token hexclave_token
]
