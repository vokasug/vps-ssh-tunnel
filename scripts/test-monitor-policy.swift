@main
struct MonitorPolicyTest {
    static func main() {
        var policy = MonitorPolicy()

        assert(policy.restartNeeded(checkPassed: false, processRunning: false))
        assert(policy.consecutiveFailures == 0)

        assert(!policy.restartNeeded(checkPassed: false, processRunning: true))
        assert(policy.consecutiveFailures == 1)
        assert(!policy.restartNeeded(checkPassed: false, processRunning: true))
        assert(policy.consecutiveFailures == 2)
        assert(policy.restartNeeded(checkPassed: false, processRunning: true))
        assert(policy.consecutiveFailures == 0)

        assert(!policy.restartNeeded(checkPassed: false, processRunning: true))
        assert(!policy.restartNeeded(checkPassed: true, processRunning: true))
        assert(!policy.restartNeeded(checkPassed: false, processRunning: true))
        assert(policy.consecutiveFailures == 1)

        assert(policy.restartNeeded(checkPassed: false, processRunning: false))
        assert(!policy.restartNeeded(checkPassed: false, processRunning: true))
        assert(policy.consecutiveFailures == 1)

        policy.reset()
        assert(policy.consecutiveFailures == 0)
        print("MonitorPolicy: all checks passed")
    }
}
