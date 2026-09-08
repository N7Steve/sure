# Fork-owned product switches live here so upstream subsystems can remain
# mergeable without becoming user-facing surfaces in this fork.
#
# Bills stays enabled in the test environment: its upstream test suite remains
# useful as executable reference coverage. Tests for the fork shell explicitly
# turn this switch off when asserting the Agenda-first experience.
Rails.application.config.x.bills_frontend_enabled = Rails.env.test?
