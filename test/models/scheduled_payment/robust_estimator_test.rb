require "test_helper"

class ScheduledPayment::RobustEstimatorTest < ActiveSupport::TestCase
  test "identical values correctly have zero uncertainty" do
    result = ScheduledPayment::RobustEstimator.call([ 100, 100, 100, 100 ], decay: 0.92)

    assert_equal 100, result.central
    assert_equal 0, result.spread
  end

  test "zero MAD with an outlier uses a fallback and winsorizes it" do
    result = ScheduledPayment::RobustEstimator.call([ 100, 100, 100, 1_000 ], decay: 0.92)

    assert_operator result.spread, :>, 0
    assert_operator result.upper, :<, 1_000
    assert_operator result.central, :<, 500
  end

  test "diagnostics expose the robust calculation for every observation" do
    diagnostics = ScheduledPayment::RobustEstimator.diagnose([ 100, 100, 100, 1_000 ], decay: 0.92)

    assert_equal 100, diagnostics.median
    assert_equal [ 100, 100, 100, 1_000 ], diagnostics.observations.map(&:raw)
    assert_operator diagnostics.robust_sigma, :>, 0
    assert_operator diagnostics.observations.last.winsorized, :<, 1_000
    assert_equal 1, diagnostics.observations.last.weight
    assert_equal diagnostics.central,
      ScheduledPayment::RobustEstimator.call([ 100, 100, 100, 1_000 ], decay: 0.92).central
  end
end
